import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers
import CoreFoundation

@main
struct ModHWManagerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

private struct CoreApp: Identifiable {
    let name: String
    let bundleIdentifier: String
    let version: String
    var id: String { bundleIdentifier }
}

private struct DeviceSummary: Decodable {
    let productType: String
    let architecture: String
    let osVersion: String
    let diskTotalBytes: UInt64
    let diskFreeBytes: UInt64
    let uptimeSeconds: Double
}

private struct PlistEntry: Identifiable {
    let key: String
    let typeName: String
    var id: String { key }
}

struct ContentView: View {
    @State private var importOpen = false
    @State private var exportOpen = false
    @State private var importedData: Data?
    @State private var fileName = "尚未导入配置"
    @State private var status = "导入 plist 后，可检查文件结构并导出原始备份。"
    @State private var entries: [PlistEntry] = []
    @State private var isValid = false
    @State private var rootType = "未知"
    @State private var coreStatus = "尚未检测 Core 服务"
    @State private var deviceSummary: DeviceSummary?
    @State private var systemStatus = "尚未读取设备信息"
    @State private var coreChecking = false
    @State private var appsLoading = false
    @State private var appInventoryStatus = "尚未读取 App 清单"
    @State private var installedApps: [CoreApp] = []
    @State private var selectedProfileBundleID = ""
    @State private var exportAsPerAppProfile = false

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("mod_hw").font(.largeTitle.bold())
                            Text("设备维护与配置管理").font(.title3).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            statusCard("Alpha11 Core", value: coreStatus, systemImage: "cpu")
                            statusCard("App 清单", value: installedApps.isEmpty ? "尚未读取" : "\(installedApps.count) 个 App", systemImage: "square.grid.2x2")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("设备信息").font(.headline)
                            if let summary = deviceSummary {
                                LabeledContent("设备型号", value: summary.productType)
                                LabeledContent("系统版本", value: summary.osVersion)
                                LabeledContent("架构", value: summary.architecture)
                                LabeledContent("存储空间", value: "\\(ByteCountFormatter.string(fromByteCount: Int64(clamping: summary.diskFreeBytes), countStyle: .file)) 可用 / \\(ByteCountFormatter.string(fromByteCount: Int64(clamping: summary.diskTotalBytes), countStyle: .file))")
                            } else {
                                Text(systemStatus).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        Button {
                            checkCore()
                            fetchInstalledApps()
                            fetchSystemSummary()
                        } label: {
                            Label(coreChecking || appsLoading ? "正在检查…" : "刷新设备状态", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("功能中心").font(.title2.bold())
                            NavigationLink { profilesPage } label: {
                                featureRow("分 App 配置", detail: "导入配置、检查字段并导出独立配置", icon: "slider.horizontal.3")
                            }
                            NavigationLink { maintenancePage } label: {
                                featureRow("备份、还原与清理", detail: "查看越狱端维护工具与执行方式", icon: "externaldrive")
                            }
                            NavigationLink { diagnosticsPage } label: {
                                featureRow("设备与插件诊断", detail: "Core 连接、App 清单、诊断状态", icon: "stethoscope")
                            }
                        }
                        Text("说明：管理器只展示已接入的功能。尚未接入 UI 的维护操作不会显示为已完成。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .navigationTitle("设备总览")
            }
            .tabItem { Label("总览", systemImage: "square.grid.2x2.fill") }

            NavigationStack { profilesPage }
                .tabItem { Label("配置", systemImage: "slider.horizontal.3") }

            NavigationStack { maintenancePage }
                .tabItem { Label("维护", systemImage: "externaldrive") }

            NavigationStack { diagnosticsPage }
                .tabItem { Label("诊断", systemImage: "stethoscope") }
        }
        .fileImporter(isPresented: $importOpen, allowedContentTypes: [.propertyList, .data]) { result in
            importPlist(result)
        }
        .fileExporter(
            isPresented: $exportOpen,
            document: RawPlistDocument(data: importedData ?? Data()),
            contentType: .propertyList,
            defaultFilename: backupName
        ) { result in
            switch result {
            case .success(let url):
                status = exportAsPerAppProfile
                    ? "分 App 配置文件已导出：\(url.lastPathComponent)"
                    : "原始备份已导出：\(url.lastPathComponent)"
            case .failure(let error): status = "文件导出失败：\(error.localizedDescription)"
            }
            exportAsPerAppProfile = false
        }
        .task {
            checkCore()
            fetchInstalledApps()
            fetchSystemSummary()
        }
    }

    private var profilesPage: some View {
        Form {
            Section {
                Label("分 App 配置管理", systemImage: "slider.horizontal.3").font(.title2.bold())
                Text("读取原作者 Hook 所需的配置字段，保留原始 plist 字节，并可按 Bundle ID 导出独立配置。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("导入 plist") { importOpen = true }
                    Spacer()
                    Button("导出原始备份") { exportAsPerAppProfile = false; exportOpen = true }
                        .disabled(importedData == nil)
                }
            }
            Section("配置文件状态") {
                LabeledContent("文件", value: fileName)
                LabeledContent("根对象", value: rootType)
                LabeledContent("字段数量", value: entries.isEmpty ? "—" : "\(entries.count)")
                LabeledContent("格式检查", value: importedData == nil ? "等待导入" : (isValid ? "有效" : "无效"))
            }
            if !entries.isEmpty {
                Section("字段清单（不显示字段值）") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.key).font(.body.monospaced())
                            Text(entry.typeName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("目标 App") {
                HStack {
                    Text("已读取 App")
                    Spacer()
                    Text("\(installedApps.count)").foregroundStyle(.secondary)
                }
                if installedApps.isEmpty {
                    Text("请先在诊断页连接 Alpha11 Core 并读取 App 清单。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("配置目标", selection: $selectedProfileBundleID) {
                        ForEach(installedApps) { app in
                            Text("\(app.name) · \(app.bundleIdentifier)").tag(app.bundleIdentifier)
                        }
                    }
                    Button("导出为所选 App 的独立配置") {
                        exportAsPerAppProfile = true
                        exportOpen = true
                    }
                    .disabled(importedData == nil || selectedProfileBundleID.isEmpty || !canExportPerAppProfile)
                    Text(canExportPerAppProfile
                         ? "当前配置通过原作者 Hook 的必需字段检查。"
                         : "需要有效的 40 位 UniqueDeviceID；启用 Wi-Fi 或蓝牙地址字段时，也必须提供有效的 12 位十六进制地址。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("配置文件应用方式") {
                Text("导出后，将对应 Bundle ID 命名的 plist 放入越狱目录 com.modhw.ios.profiles；当前版本只负责生成文件，不会自动写入越狱目录或切换 Hook 配置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("操作结果") { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("配置管理")
    }

    private var maintenancePage: some View {
        List {
            Section {
                Label("App 数据维护", systemImage: "externaldrive.fill").font(.title2.bold())
                Text("这些脚本目前由越狱端命令行工具执行；管理器尚未接入远程执行 API。先完成备份和校验，再考虑清理或还原。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("备份") {
                commandRow("备份指定 App", command: "/var/jb/usr/bin/mod-hw-app-backup <BundleID>")
                commandRow("验证备份完整性", command: "/var/jb/usr/bin/mod-hw-app-backup-verify <备份文件>")
            }
            Section("还原与清理") {
                commandRow("还原指定 App", command: "/var/jb/usr/bin/mod-hw-app-restore <BundleID> <备份文件> --confirm")
                commandRow("清理指定 App", command: "/var/jb/usr/bin/mod-hw-app-clean <BundleID> --confirm")
                Text("还原和清理会改变目标 App 数据。未确认备份可用前不要执行。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Section("配置备份") {
                commandRow("备份配置", command: "/var/jb/usr/bin/mod-hw-config-backup")
                commandRow("还原配置", command: "/var/jb/usr/bin/mod-hw-config-restore <备份文件>")
            }
        }
        .navigationTitle("备份与维护")
    }

    private var diagnosticsPage: some View {
        List {
            Section("Alpha11 Core") {
                LabeledContent("服务地址", value: "127.0.0.1:18081")
                LabeledContent("连接状态", value: coreStatus)
                Button(coreChecking ? "检测中…" : "检测 Core 连接") { checkCore() }
                    .disabled(coreChecking)
            }
            Section("App 清单") {
                LabeledContent("读取状态", value: appInventoryStatus)
                LabeledContent("已读取数量", value: "\(installedApps.count)")
                Button(appsLoading ? "读取中…" : "重新读取 App 清单") { fetchInstalledApps() }
                    .disabled(appsLoading)
                ForEach(installedApps) { app in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                        Text(app.bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !app.version.isEmpty { Text("版本：\(app.version)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("诊断工具") {
                Text("Keychain 诊断只读取应用签名 Entitlements，不读取或删除 Keychain 项目。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("命令：/var/jb/usr/bin/mod-hw-keychain-diagnose <BundleID>")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("设备自检命令：/var/jb/usr/bin/mod-hw-selftest")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("设备诊断")
    }

    private func statusCard(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func commandRow(_ title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(command).font(.caption.monospaced()).textSelection(.enabled)
            Button {
                UIPasteboard.general.string = command
            } label: {
                Label("复制命令", systemImage: "doc.on.doc")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func checkCore() {
        coreChecking = true
        coreStatus = "正在连接本机 Core…"
        Task {
            defer { coreChecking = false }
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/status")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 3
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    coreStatus = "Core 返回异常响应"
                    return
                }
                guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["ok"] as? Bool == true,
                      let service = payload["service"] as? String,
                      let version = payload["version"] as? String,
                      payload["mode"] as? String == "read-only" else {
                    coreStatus = "响应格式不匹配（不是预期的 Core 服务）"
                    return
                }
                coreStatus = "已连接：\(service) · v\(version)"
            } catch {
                coreStatus = "未连接：\(error.localizedDescription)"
            }
        }
    }

    private func fetchSystemSummary() {
        systemStatus = "正在读取设备信息…"
        Task {
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/system")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 4
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let summary = try JSONDecoder().decode(DeviceSummary.self, from: data)
                deviceSummary = summary
                systemStatus = "设备信息已更新"
            } catch {
                deviceSummary = nil
                systemStatus = "读取失败：\\(error.localizedDescription)"
            }
        }
    }

    private func fetchInstalledApps() {
        appsLoading = true
        appInventoryStatus = "正在读取本机 App 清单…"
        Task {
            defer { appsLoading = false }
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/apps")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 5
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["ok"] as? Bool == true,
                      let rows = payload["apps"] as? [[String: Any]] else {
                    appInventoryStatus = "Core 返回的 App 清单格式无效"
                    installedApps = []
                    return
                }
                installedApps = rows.compactMap { row in
                    guard let name = row["name"] as? String,
                          let bundle = row["bundleIdentifier"] as? String else { return nil }
                    return CoreApp(name: name, bundleIdentifier: bundle, version: row["version"] as? String ?? "")
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !installedApps.contains(where: { $0.bundleIdentifier == selectedProfileBundleID }) {
                    selectedProfileBundleID = installedApps.first?.bundleIdentifier ?? ""
                }
                appInventoryStatus = "已读取 \(installedApps.count) 个 App（只读清单）"
            } catch {
                installedApps = []
                appInventoryStatus = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    private var canExportPerAppProfile: Bool {
        guard let data = importedData,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let udid = dictionary["UniqueDeviceID"] as? String,
              udid.count == 40,
              udid.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            return false
        }
        for (enabledKey, valueKey) in [("WifiAddressData", "WifiAddress"), ("BluetoothAddressData", "BluetoothAddress")] {
            if (dictionary[enabledKey] as? Bool) == true {
                guard let address = dictionary[valueKey] as? String else { return false }
                let normalized = address.replacingOccurrences(of: ":", with: "")
                guard normalized.count == 12,
                      normalized.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
                    return false
                }
            }
        }
        return true
    }

    private var backupName: String {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if exportAsPerAppProfile && !selectedProfileBundleID.isEmpty { return selectedProfileBundleID }
        return base.isEmpty ? "plist-backup" : "\(base)-backup"
    }

    private func importPlist(_ result: Result<URL, Error>) {
        do {
            let selectedURL = try result.get()
            let hasSecurityScope = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { selectedURL.stopAccessingSecurityScopedResource() }
            }

            // Coordinate reads from Files, iCloud Drive, and third-party File Providers.
            // Parse only a coordinated read URL while the security scope is active.
            var coordinationError: NSError?
            var readResult: Result<Data, Error>?
            NSFileCoordinator(filePresenter: nil).coordinate(
                readingItemAt: selectedURL,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                readResult = Result {
                    let values = try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                    guard values.isRegularFile == true, values.isDirectory != true else {
                        throw CocoaError(.fileReadUnsupportedScheme)
                    }
                    return try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                }
            }
            if let coordinationError { throw coordinationError }
            guard let readResult else {
                throw CocoaError(.fileReadUnknown)
            }
            let data = try readResult.get()

            var format = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )

            importedData = data
            fileName = selectedURL.lastPathComponent
            isValid = true
            if let dictionary = object as? [String: Any] {
                rootType = "Dictionary"
                entries = dictionary.keys.sorted().map { key in
                    PlistEntry(key: key, typeName: Self.typeName(dictionary[key]))
                }
                status = "导入成功（\(format == .binary ? "Binary" : "XML") plist）。已读取字段名称和类型；字段值未展示，导出保留原始字节。"
            } else if let array = object as? [Any] {
                rootType = "Array"
                entries = array.enumerated().map { index, value in
                    PlistEntry(key: "[\(index)]", typeName: Self.typeName(value))
                }
                status = "导入成功。根对象为 Array，共 \(array.count) 项；导出保留原始字节。"
            } else {
                rootType = Self.typeName(object)
                entries = []
                status = "导入成功。根对象类型：\(rootType)。原始文件字节已保留。"
            }
        } catch {
            importedData = nil
            entries = []
            rootType = "无法解析"
            isValid = false
            fileName = "导入失败"
            status = "导入失败（\(String(reflecting: type(of: error)))）：\(error.localizedDescription)"
        }
    }

    private static func typeName(_ value: Any?) -> String {
        guard let value else { return "缺失" }
        if value is String { return "String" }
        if value is Data { return "Data" }
        if value is Date { return "Date" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "Boolean" : "Number"
        }
        if value is [String: Any] { return "Dictionary" }
        if value is [Any] { return "Array" }
        return String(describing: type(of: value))
    }
}

struct RawPlistDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try PropertyListSerialization.propertyList(from: contents, options: [], format: nil)
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
