import SwiftUI
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
    @State private var coreChecking = false
    @State private var appsLoading = false
    @State private var appInventoryStatus = "尚未读取 App 清单"
    @State private var installedApps: [CoreApp] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("配置文件检查器", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
                        Text("只读检查 plist 文件结构、字段名称与数据类型。不会修改设备身份字段，也不会向系统服务写入配置。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("导入 plist") { importOpen = true }
                        Spacer()
                        Button("导出原始备份") { exportOpen = true }
                            .disabled(importedData == nil).buttonStyle(.borderedProminent)
                    }
                }
                Section("文件状态") {
                    LabeledContent("文件", value: fileName)
                    LabeledContent("根对象", value: rootType)
                    LabeledContent("字段数量", value: entries.isEmpty ? "—" : "\(entries.count)")
                    HStack {
                        Text("格式检查")
                        Spacer()
                        if importedData == nil {
                            Text("等待导入").foregroundStyle(.secondary)
                        } else {
                            Label(isValid ? "有效" : "无效", systemImage: isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(isValid ? .green : .red)
                        }
                    }
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
                Section("越狱 Core 连接（只读检测）") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("127.0.0.1:18081")
                                .font(.system(.body, design: .monospaced))
                            Text(coreStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(coreChecking ? "检测中…" : "检测连接") {
                            checkCore()
                        }
                        .disabled(coreChecking)
                    }
                    Button(appsLoading ? "读取中…" : "读取已安装 App 清单") {
                        fetchInstalledApps()
                    }
                    .disabled(appsLoading)
                    Text(appInventoryStatus).font(.footnote).foregroundStyle(.secondary)
                    if !installedApps.isEmpty {
                        ForEach(installedApps) { app in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                Text(app.bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if !app.version.isEmpty {
                                    Text("版本：\(app.version)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("仅请求只读 /status 和 /apps 接口；不会读取或切换配置，也不会修改设备数据。需要先在越狱环境安装并启动 Alpha11 Core。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("运行说明") {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                    Text("本工具仅检查用户选取的文件。iOS 沙盒不会自动授予它读取越狱目录的权限；请通过文件管理器手动导入需要检查的 plist。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("mod_hw 管理器")
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
                case .success(let url): status = "原始备份已导出：\(url.lastPathComponent)"
                case .failure(let error): status = "备份导出失败：\(error.localizedDescription)"
                }
            }
        }
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
                appInventoryStatus = "已读取 \(installedApps.count) 个 App（只读清单）"
            } catch {
                installedApps = []
                appInventoryStatus = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    private var backupName: String {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
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
