import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers
import CoreFoundation
import Darwin

@main
struct ModHWManagerApp: App {
    @StateObject private var profileStore = ProfileStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(profileStore) }
    }
}

private struct CoreApp: Identifiable {
    let name: String
    let bundleIdentifier: String
    let version: String
    var id: String { bundleIdentifier }
}

private struct MaintenanceTool: Decodable, Identifiable {
    let name: String
    let path: String
    let installed: Bool
    var id: String { name }
}

private struct AppProfile: Decodable, Identifiable {
    let bundleIdentifier: String
    let valid: Bool
    let path: String
    var id: String { bundleIdentifier }
}

private struct BackupRecord: Decodable, Identifiable {
    let archive: String
    let bundleIdentifier: String
    let containerIdentifier: String
    let createdAt: String
    let sha256: String
    let sizeBytes: UInt64
    var id: String { archive }
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

private struct MaintenanceRecord: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let action: String
    let target: String
    let success: Bool
    let detail: String
}

struct ContentView: View {
    @EnvironmentObject private var profileStore: ProfileStore
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
    @State private var maintenanceTools: [MaintenanceTool] = []
    @State private var backups: [BackupRecord] = []
    @State private var backupsStatus = "尚未读取备份清单"
    @State private var toolsStatus = "尚未检查维护工具"
    @State private var appProfiles: [AppProfile] = []
    @State private var profilesStatus = "尚未读取已安装配置"
    @State private var coreChecking = false
    @State private var appsLoading = false
    @State private var appInventoryStatus = "尚未读取 App 清单"
    @State private var installedApps: [CoreApp] = []
    @State private var selectedProfileBundleID = ""
    @State private var maintenanceBundleID = ""
    @State private var maintenanceArchiveName = ""
    @State private var helperPaired = false
    @State private var helperStatus = "尚未检测权限助手"
    @State private var maintenanceRunning = false
    @State private var maintenanceResult = ""
    @State private var pendingMaintenanceAction: String?
    @State private var showMaintenanceConfirmation = false
    @State private var exportAsPerAppProfile = false
    @State private var operationRecords: [MaintenanceRecord] = []

    var body: some View {
        TabView {
            NavigationStack { homePage }
                .tabItem { Label("首页", systemImage: "house.fill") }
            NavigationStack { recordsPage }
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
            NavigationStack { settingsPage }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
            NavigationStack { aboutPage }
                .tabItem { Label("关于", systemImage: "info.circle.fill") }
        }
        .tint(Color(red: 0.10, green: 0.43, blue: 0.92))
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
            loadOperationRecords()
            checkCore()
            fetchInstalledApps()
            fetchSystemSummary()
            fetchMaintenanceTools()
            fetchAppProfiles()
            fetchBackups()
            checkMaintenanceHelper()
        }
    }

    private var homePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(red: 0.08, green: 0.38, blue: 0.88), Color(red: 0.22, green: 0.68, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("mod_hw_for_ios V2").font(.system(size: 25, weight: .bold, design: .rounded))
                                Text("iOS 设备管理中心 · Rootless").font(.subheadline).foregroundStyle(.white.opacity(0.88))
                            }
                            Spacer()
                            Image(systemName: "apple.logo").font(.system(size: 34, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                        }
                        HStack(spacing: 8) {
                            Label(helperPaired ? "权限助手已配对" : "权限助手待配对", systemImage: helperPaired ? "checkmark.shield.fill" : "exclamationmark.shield")
                            Text("·")
                            Text(deviceSummary?.osVersion ?? "设备信息待读取")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, minHeight: 148)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.blue.opacity(0.16), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("设备状态").font(.headline)
                        Spacer()
                        Button("刷新") {
                            checkCore(); fetchInstalledApps(); fetchSystemSummary()
                            fetchMaintenanceTools(); fetchAppProfiles(); fetchBackups(); checkMaintenanceHelper()
                        }
                        .font(.subheadline)
                    }
                    HStack(spacing: 10) {
                        statusCard("Core", value: coreStatus, systemImage: "cpu")
                        statusCard("已安装 App", value: installedApps.isEmpty ? "尚未读取" : "\(installedApps.count) 个", systemImage: "square.grid.2x2")
                    }
                    if let summary = deviceSummary {
                        HStack {
                            Label(summary.productType, systemImage: "iphone")
                            Spacer()
                            Text("iOS \(summary.osVersion)")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: summary.diskFreeBytes), countStyle: .file) + " 可用")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("功能中心").font(.title3.bold())
                        Spacer()
                        Text("快捷入口").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        dashboardTile("备份中心", detail: "App 数据与配置备份", icon: "externaldrive.fill", color: .blue) {
                            backupCenterPage
                        }
                        dashboardTile("还原中心", detail: "校验备份并安全还原", icon: "arrow.counterclockwise.circle.fill", color: .green) {
                            restoreCenterPage
                        }
                        dashboardTile("清理中心", detail: "指定 App 深度清理", icon: "sparkles", color: .purple) {
                            cleanupPage
                        }
                        dashboardTile("改机管理", detail: "全局设备参数配置", icon: "slider.horizontal.3", color: .orange) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            )
                                .environmentObject(profileStore)
                        }
                        dashboardTile("分 App 改机", detail: "按 Bundle ID 独立配置", icon: "square.grid.2x2.fill", color: .teal) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            )
                                .environmentObject(profileStore)
                        }
                        dashboardTile("模板管理", detail: "创建、复制、导入与导出配置模板", icon: "shippingbox.fill", color: .indigo) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            )
                                .environmentObject(profileStore)
                        }
                        dashboardTile("系统诊断", detail: "Core、插件与权限检查", icon: "stethoscope", color: .cyan) {
                            NavigationStack { diagnosticsPage }
                        }
                        dashboardTile("IPA 多开", detail: "打开原作者 IPA 编辑器", icon: "square.stack.3d.up.fill", color: .pink) {
                            IPAEditorView()
                        }
                    }
                }
                Text("维护操作由已配对的 Root Helper 执行；Core 只提供只读设备信息。清理与还原均要求明确确认，并保留备份或回滚快照。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("首页")
    }

    private func dashboardTile<Destination: View>(_ title: String, detail: String, icon: String, color: Color, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.blue.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var backupCenterPage: some View {
        Form {
            Section {
                Text("为指定 App 创建本地数据容器备份。备份由 Root Helper 调用原有脚本完成，并生成 SHA-256 清单。")
                    .font(.footnote).foregroundStyle(.secondary)
                appTargetPicker
                Button(maintenanceRunning ? "正在备份…" : "开始备份") { performMaintenance("backup") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                Button("备份全局与分 App Hook 配置") { performMaintenance("config-backup") }
                    .disabled(!helperPaired || maintenanceRunning)
            }
            Section("备份记录") {
                if backups.isEmpty {
                    Text(backupsStatus).font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(backup.bundleIdentifier).font(.subheadline.weight(.semibold))
                            Text(backup.archive).font(.caption.monospaced()).textSelection(.enabled)
                            Text("SHA-256：\(backup.sha256)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Button("选用此备份") {
                                maintenanceBundleID = backup.bundleIdentifier
                                maintenanceArchiveName = backup.archive
                            }
                        }
                    }
                }
                Button("刷新备份记录") { fetchBackups() }
            }
            if !maintenanceResult.isEmpty { Section("执行结果") { Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled) } }
        }
        .navigationTitle("备份中心")
    }

    private var restoreCenterPage: some View {
        Form {
            Section("还原目标") {
                appTargetPicker
                TextField("备份文件名", text: $maintenanceArchiveName).font(.footnote.monospaced())
                Button("验证备份完整性") { performMaintenance("verify") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceArchiveName.isEmpty)
                Button("开始还原") {
                    pendingMaintenanceAction = "restore"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty || maintenanceArchiveName.isEmpty)
            }
            Section("全局与分 App 配置") {
                Button("还原最近一次 Hook 配置备份") {
                    pendingMaintenanceAction = "config-restore"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning)
                Text("会校验归档 SHA-256 与内部路径，并保留还原前的全局和分 App 配置快照。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("可用 App 数据备份") {
                ForEach(backups.filter { maintenanceBundleID.isEmpty || $0.bundleIdentifier == maintenanceBundleID }) { backup in
                    Button {
                        maintenanceBundleID = backup.bundleIdentifier
                        maintenanceArchiveName = backup.archive
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.bundleIdentifier).font(.subheadline.weight(.semibold))
                            Text(backup.archive).font(.caption.monospaced())
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: backup.sizeBytes), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("刷新备份列表") { fetchBackups() }
            }
            if !maintenanceResult.isEmpty { Section("执行结果") { Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled) } }
        }
        .confirmationDialog("确认执行配置还原", isPresented: $showMaintenanceConfirmation, titleVisibility: .visible) {
            if pendingMaintenanceAction == "restore" {
                Button("确认还原 App 数据", role: .destructive) { performMaintenance("restore") }
            } else if pendingMaintenanceAction == "config-restore" {
                Button("确认还原全局与分 App 配置", role: .destructive) { performMaintenance("config-restore") }
            }
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text(pendingMaintenanceAction == "config-restore"
                 ? "将恢复最近一次全局与分 App Hook 配置备份，并保留还原前快照。"
                 : "还原前会再次验证备份，并创建当前 App 容器回滚快照。")
        }
        .navigationTitle("还原中心")
    }

    private var cleanupPage: some View {
        Form {
            Section("清理目标") {
                appTargetPicker
                Text("将清空指定 App 的整个本地数据容器，而不只是 Caches/tmp。执行前自动备份并校验，清理时创建回滚快照。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("立即清理") {
                    pendingMaintenanceAction = "clean"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
            }
            Section("清理范围") {
                Label("App 本地容器：Documents、Library、Caches 等", systemImage: "checkmark.circle.fill")
                Label("自动备份、SHA-256 校验与失败回滚", systemImage: "checkmark.shield.fill")
                Label("Keychain、App Groups、共享容器和云端数据不在范围内", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            if !maintenanceResult.isEmpty { Section("执行结果") { Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled) } }
        }
        .confirmationDialog("确认深度清理指定 App", isPresented: $showMaintenanceConfirmation, titleVisibility: .visible) {
            Button("确认清理并自动备份", role: .destructive) { performMaintenance("clean") }
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text("此操作将清空所选 App 的整个本地数据容器。请先完全退出目标 App。")
        }
        .navigationTitle("清理中心")
    }

    private var appTargetPicker: some View {
        Group {
            if !installedApps.isEmpty {
                Picker("选择目标 App", selection: $maintenanceBundleID) {
                    Text("请选择").tag("")
                    ForEach(installedApps) { app in
                        Text(app.name).tag(app.bundleIdentifier)
                    }
                }
            } else {
                TextField("Bundle ID", text: $maintenanceBundleID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
    }

    private var recordsPage: some View {
        List {
            Section {
                HStack {
                    Text("共 \(operationRecords.count) 条操作记录").foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { loadOperationRecords() }
                }
            }
            if operationRecords.isEmpty {
                VStack(spacing: 8) { Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary); Text("暂无操作记录").font(.headline); Text("备份、校验、还原、清理和配置应用结果会显示在这里。").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(operationRecords) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.action).font(.subheadline.weight(.semibold))
                            Spacer()
                            Label(record.success ? "成功" : "失败", systemImage: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption).foregroundStyle(record.success ? .green : .red)
                        }
                        Text(record.target).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(record.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.tertiary)
                        if !record.detail.isEmpty { Text(record.detail).font(.caption).lineLimit(3).textSelection(.enabled) }
                    }
                    .padding(.vertical, 4)
                }
            }
            Button("清空操作记录", role: .destructive) {
                operationRecords = []
                UserDefaults.standard.removeObject(forKey: "iDeviceLabMaintenanceRecordsV1")
            }
        }
        .navigationTitle("操作记录")
    }

    private var settingsPage: some View {
        Form {
            Section("运行状态") {
                LabeledContent("Alpha11 Core", value: coreStatus)
                LabeledContent("Root Helper", value: helperStatus)
                LabeledContent("维护工具", value: "\(maintenanceTools.filter(\.installed).count) / \(maintenanceTools.count)")
                LabeledContent("备份记录", value: "\(backups.count)")
                Button("刷新所有状态") {
                    checkCore(); fetchInstalledApps(); fetchSystemSummary()
                    fetchMaintenanceTools(); fetchAppProfiles(); fetchBackups(); checkMaintenanceHelper()
                }
            }
            Section("权限助手配对") {
                commandRow("复制首次配对命令", command: "su -c '/var/jb/usr/bin/mod-hw-manager-pair \(getpid())'")
                Text("配对将当前管理器进程的代码签名 CDHash 固定到 Root Helper。管理器更新后若签名变化，需要重新配对。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("维护与验收") {
                NavigationLink("高级维护与 iPhone 12 最终验收") { maintenancePage }
            }
            Section("配置文件") {
                LabeledContent("当前导入文件", value: fileName)
                LabeledContent("配置解析", value: importedData == nil ? "未导入" : (isValid ? "有效" : "无效"))
                NavigationLink("打开设备配置管理") { profilesPage }
                NavigationLink("打开分 App 环境管理") {
                    ProfileManagerView(
                        availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                        onOperation: { action, success, detail in
                            recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                        }
                    )
                        .environmentObject(profileStore)
                }
            }
        }
        .navigationTitle("设置")
    }

    private var aboutPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "apple.logo").font(.system(size: 48)).foregroundStyle(.blue)
                Text("mod_hw_for_ios V2").font(.title.bold())
                Text("iOS 设备配置与维护管理器").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("版本", value: "2.0.0")
                    LabeledContent("运行模式", value: "Rootless")
                    LabeledContent("最低系统", value: "iOS 16.0")
                    LabeledContent("项目分支", value: "mod-hw-alpha11")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                Text("保留原作者 Hook 与 IPA 编辑器模块；Root Helper 仅开放固定维护动作，Core 维持只读。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("关于")
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
            Section("越狱端已安装配置") {
                Text(profilesStatus).font(.footnote).foregroundStyle(.secondary)
                Button("刷新配置清单") { fetchAppProfiles() }
                if appProfiles.isEmpty {
                    Text("尚未发现配置文件。配置目录：/var/mobile/Library/Preferences/com.modhw.ios.profiles")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(appProfiles) { profile in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(profile.bundleIdentifier).font(.subheadline.monospaced())
                                Spacer()
                                Label(profile.valid ? "格式有效" : "格式无效",
                                      systemImage: profile.valid ? "checkmark.circle.fill" : "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(profile.valid ? .green : .orange)
                            }
                            Text(profile.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("此清单只读取文件名和 plist 格式，不显示配置字段值，也不代表目标 App 已加载该配置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("配置文件应用方式") {
                Text("管理器当前负责生成独立配置；Core 可读取越狱端已安装配置清单。将导出的 plist 放入上方目录后，目标 App 下次启动时由原作者 Hook 按 Bundle ID 选择配置。")
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
                Text("管理器通过独立 Root Helper 执行固定白名单操作；Core 继续保持只读。首次安装或管理器更新后，需要 root 配对一次。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Root 权限助手") {
                LabeledContent("连接状态", value: helperStatus)
                Button("重新检测权限助手") { checkMaintenanceHelper() }
                commandRow("首次配对 / 更新后重新配对", command: "su -c '/var/jb/usr/bin/mod-hw-manager-pair \(getpid())'")
                Text("复制配对命令后，在越狱终端以 root 执行并输入 PAIR 确认。配对绑定当前管理器签名，不接受其他 mobile 进程。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("目标 App") {
                if !installedApps.isEmpty {
                    Picker("已安装 App", selection: $maintenanceBundleID) {
                        Text("选择 App").tag("")
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.bundleIdentifier)
                        }
                    }
                }
                TextField("Bundle ID（例如 com.example.app）", text: $maintenanceBundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("刷新 App 清单") { fetchInstalledApps() }
            }
            Section("备份与校验") {
                HStack {
                    Text(backupsStatus).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { fetchBackups() }
                }
                if backups.isEmpty {
                    Text("尚无可识别的备份，或备份目录尚未创建。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.bundleIdentifier).font(.subheadline.weight(.semibold))
                            Text(backup.archive).font(.caption.monospaced()).textSelection(.enabled)
                            HStack {
                                Text(backup.createdAt)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: backup.sizeBytes), countStyle: .file))
                            }.font(.caption).foregroundStyle(.secondary)
                            Text("SHA-256：\(backup.sha256)")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            Button("填入校验文件名") { maintenanceArchiveName = backup.archive }
                                .font(.caption)
                        }
                    }
                }
                TextField("备份文件名（用于校验或还原）", text: $maintenanceArchiveName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button(maintenanceRunning ? "正在执行…" : "直接备份所选 App") { performMaintenance("backup") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(maintenanceRunning ? "正在执行…" : "直接验证备份完整性") { performMaintenance("verify") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceArchiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("还原与清理") {
                Button("还原指定 App") {
                    pendingMaintenanceAction = "restore"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty || maintenanceArchiveName.isEmpty)
                Button("清理指定 App") {
                    pendingMaintenanceAction = "clean"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                Text("还原前会先校验所选备份；还原脚本保留回滚快照。清理脚本会先自动备份并校验，再清理目标容器。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if maintenanceRunning || !maintenanceResult.isEmpty {
                Section("最近一次操作结果") {
                    if maintenanceRunning { ProgressView("正在等待 Root Helper 返回结果…") }
                    Text(maintenanceResult.isEmpty ? "操作执行中" : maintenanceResult)
                        .font(.footnote.monospaced()).textSelection(.enabled)
                }
            }
            Section("配置备份与诊断") {
                Button("直接备份配置") { performMaintenance("config-backup") }
                    .disabled(!helperPaired || maintenanceRunning)
                Button("还原最近一次有效配置备份") {
                    pendingMaintenanceAction = "config-restore"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning)
                Button("诊断配置文件") { performMaintenance("diagnose-config") }
                    .disabled(!helperPaired || maintenanceRunning)
                Button("诊断所选 App 的 Keychain Entitlements") { performMaintenance("keychain-diagnose") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                Button("运行只读设备自检") { performMaintenance("selftest") }
                    .disabled(!helperPaired || maintenanceRunning)
                Button("运行 iPhone 12 / iOS 16.2 最终验收") { performMaintenance("acceptance-iphone12") }
                    .disabled(!helperPaired || maintenanceRunning)
                Text("最终验收只检查机型、系统版本、安装包、Root Helper 配对和只读自检，不执行备份、还原或清理。配置还原会先保留当前配置快照；Keychain 诊断仅读取签名 Entitlements。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("确认执行破坏性操作", isPresented: $showMaintenanceConfirmation, titleVisibility: .visible) {
            Button("确认还原 App", role: .destructive) { performMaintenance("restore") }
                .disabled(pendingMaintenanceAction != "restore")
            Button("确认清理 App", role: .destructive) { performMaintenance("clean") }
                .disabled(pendingMaintenanceAction != "clean")
            Button("确认还原配置", role: .destructive) { performMaintenance("config-restore") }
                .disabled(pendingMaintenanceAction != "config-restore")
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text("此操作会改变所选 App 或配置数据。请确认目标和备份状态无误。")
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
            Section("越狱维护工具") {
                Text(toolsStatus).font(.footnote).foregroundStyle(.secondary)
                Button("刷新工具安装状态") { fetchMaintenanceTools() }
                ForEach(maintenanceTools) { tool in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name).font(.subheadline.monospaced())
                            Text(tool.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(tool.installed ? "已安装" : "缺失", systemImage: tool.installed ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(tool.installed ? .green : .orange)
                    }
                }
            }
            Section("诊断工具") {
                Text("Keychain 诊断只读取应用签名 Entitlements，不读取或删除 Keychain 项目。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("命令：/var/jb/usr/bin/mod-hw-keychain-diagnose <BundleID>")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("直接诊断所选 App Keychain Entitlements") { performMaintenance("keychain-diagnose") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                Text("设备自检命令：/var/jb/usr/bin/mod-hw-selftest")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("直接运行只读设备自检") { performMaintenance("selftest") }
                    .disabled(!helperPaired || maintenanceRunning)
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

    private func safeShellArgument(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "'<请填写>'" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    private func loadOperationRecords() {
        guard let data = UserDefaults.standard.data(forKey: "iDeviceLabMaintenanceRecordsV1"),
              let decoded = try? JSONDecoder().decode([MaintenanceRecord].self, from: data) else {
            operationRecords = []
            return
        }
        operationRecords = decoded.sorted { $0.date > $1.date }
    }

    private func recordOperation(_ action: String, target: String, success: Bool, detail: String) {
        let labels = [
            "backup": "App 数据备份", "verify": "备份完整性校验",
            "restore": "App 数据还原", "clean": "App 深度清理",
            "config-backup": "全局配置备份", "config-restore": "全局配置还原",
            "keychain-diagnose": "Keychain 权限诊断", "diagnose-config": "配置诊断",
            "selftest": "设备只读自检", "acceptance-iphone12": "iPhone 12 最终验收"
        ]
        operationRecords.insert(MaintenanceRecord(date: Date(), action: labels[action] ?? action,
                                                  target: target.isEmpty ? "设备 / 全局" : target,
                                                  success: success, detail: detail), at: 0)
        if operationRecords.count > 100 { operationRecords = Array(operationRecords.prefix(100)) }
        if let data = try? JSONEncoder().encode(operationRecords) {
            UserDefaults.standard.set(data, forKey: "iDeviceLabMaintenanceRecordsV1")
        }
    }

    private func checkMaintenanceHelper() {
        helperStatus = "正在检测 Root Helper…"
        Task {
            do {
                let result = try await MaintenanceClient.request(action: "status")
                helperPaired = result.paired == true
                helperStatus = helperPaired ? "已配对，可直接执行" : "助手在线，管理器尚未配对"
            } catch {
                helperPaired = false
                helperStatus = "未连接：\(error.localizedDescription)"
            }
        }
    }

    private func performMaintenance(_ action: String) {
        let bundleID = maintenanceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let archive = maintenanceArchiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["backup", "restore", "clean", "keychain-diagnose"].contains(action) && bundleID.isEmpty {
            maintenanceResult = "请先选择或填写目标 App 的 Bundle ID。"
            return
        }
        if ["verify", "restore"].contains(action) && archive.isEmpty {
            maintenanceResult = "请先选择备份文件。"
            return
        }
        maintenanceRunning = true
        maintenanceResult = "正在执行 \(action)…"
        Task {
            defer { maintenanceRunning = false }
            do {
                if action == "restore" {
                    let verification = try await MaintenanceClient.request(action: "verify", archive: archive)
                    guard verification.ok else {
                        let detail = verification.output ?? verification.error ?? "无详细输出"
                        maintenanceResult = "还原已阻止：备份校验失败。\n\(detail)"
                        recordOperation("restore", target: bundleID, success: false, detail: "还原前校验失败：\(detail)")
                        return
                    }
                }
                let result = try await MaintenanceClient.request(
                    action: action,
                    bundleID: bundleID.isEmpty ? nil : bundleID,
                    archive: archive.isEmpty ? nil : archive,
                    confirm: ["restore", "clean", "config-restore"].contains(action)
                )
                maintenanceResult = result.ok
                    ? (result.output ?? "操作完成。")
                    : (result.error ?? result.output ?? "操作失败，退出码：\(result.exitCode ?? -1)")
                recordOperation(action, target: bundleID.isEmpty ? archive : bundleID, success: result.ok, detail: result.output ?? result.error ?? "")
                if result.ok && ["backup", "restore", "clean"].contains(action) {
                    fetchBackups()
                }
                checkMaintenanceHelper()
            } catch {
                maintenanceResult = "操作失败：\(error.localizedDescription)"
                recordOperation(action, target: bundleID.isEmpty ? archive : bundleID, success: false, detail: error.localizedDescription)
                checkMaintenanceHelper()
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
                systemStatus = "读取失败：\(error.localizedDescription)"
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

    private func fetchMaintenanceTools() {
        toolsStatus = "正在检查越狱端工具…"
        Task {
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/tools")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 4
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["ok"] as? Bool == true,
                      let rows = payload["tools"] as? [[String: Any]] else {
                    throw URLError(.cannotParseResponse)
                }
                maintenanceTools = rows.compactMap { row in
                    guard let name = row["name"] as? String,
                          let path = row["path"] as? String,
                          let installed = row["installed"] as? Bool else { return nil }
                    return MaintenanceTool(name: name, path: path, installed: installed)
                }
                let count = maintenanceTools.filter(\.installed).count
                toolsStatus = "已检测 \(count)/\(maintenanceTools.count) 个维护工具"
            } catch {
                maintenanceTools = []
                toolsStatus = "检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func fetchBackups() {
        backupsStatus = "正在读取本机备份清单…"
        Task {
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/backups")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 4
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["ok"] as? Bool == true else {
                    throw URLError(.cannotParseResponse)
                }
                let rows = payload["backups"] ?? []
                backups = try JSONDecoder().decode([BackupRecord].self, from: JSONSerialization.data(withJSONObject: rows))
                backupsStatus = "已读取 \(backups.count) 个备份记录（只读）"
            } catch {
                backups = []
                backupsStatus = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    private func fetchAppProfiles() {
        profilesStatus = "正在读取越狱端配置清单…"
        Task {
            do {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/profiles")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 4
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["ok"] as? Bool == true,
                      let rows = payload["profiles"] as? [[String: Any]] else {
                    throw URLError(.cannotParseResponse)
                }
                appProfiles = rows.compactMap { row in
                    guard let bundle = row["bundleIdentifier"] as? String,
                          let valid = row["valid"] as? Bool,
                          let path = row["path"] as? String else { return nil }
                    return AppProfile(bundleIdentifier: bundle, valid: valid, path: path)
                }
                profilesStatus = "已读取 \(appProfiles.count) 个分 App 配置"
            } catch {
                appProfiles = []
                profilesStatus = "读取失败：\(error.localizedDescription)"
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

struct MaintenanceOperationResult: Decodable {
    let ok: Bool
    let paired: Bool?
    let helper: String?
    let action: String?
    let exitCode: Int?
    let output: String?
    let error: String?
    let outputTruncated: Bool?
}

enum MaintenanceClient {
    private static let socketPath = "/var/run/com.idevelab.maintenance.sock"

    static func request(action: String, bundleID: String? = nil, archive: String? = nil, profile: [String: Any]? = nil, confirm: Bool = false) async throws -> MaintenanceOperationResult {
        var payload: [String: Any] = ["action": action]
        if let bundleID { payload["bundleID"] = bundleID }
        if let archive { payload["archive"] = archive }
        if let profile { payload["profile"] = profile }
        if confirm { payload["confirm"] = true }
        var requestData = try JSONSerialization.data(withJSONObject: payload, options: [])
        requestData.append(0x0A)
        return try await Task.detached(priority: .userInitiated) {
            try perform(requestData: requestData)
        }.value
    }

    private static func perform(requestData: Data) throws -> MaintenanceOperationResult {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: "MaintenanceHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建本地套接字。"]) }
        defer { Darwin.close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw NSError(domain: "MaintenanceHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Root Helper 套接字路径过长。"])
        }
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw NSError(domain: "MaintenanceHelper", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "无法连接 Root Helper（\(String(cString: strerror(errno)))）。"])
        }

        var timeout = timeval()
        timeout.tv_sec = 300
        timeout.tv_usec = 0
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try requestData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw NSError(domain: "MaintenanceHelper", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "发送维护请求失败。"])
                }
                offset += count
            }
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var receivedLine = false
        while responseData.count < 131072 && !receivedLine {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw NSError(domain: "MaintenanceHelper", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Root Helper 未返回有效结果。"])
            }
            if let newline = buffer[..<count].firstIndex(of: 0x0A) {
                responseData.append(contentsOf: buffer[..<newline])
                receivedLine = true
            } else {
                responseData.append(contentsOf: buffer.prefix(count))
            }
        }
        guard receivedLine else {
            throw NSError(domain: "MaintenanceHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Root Helper 响应超过长度限制。"])
        }
        return try JSONDecoder().decode(MaintenanceOperationResult.self, from: responseData)
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
