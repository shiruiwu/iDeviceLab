import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers
import CoreFoundation
import Darwin
import Security

// Build 11 starts with UIKit only. SwiftUI and ProfileStore are not instantiated
// until the user explicitly enters the full manager. This distinguishes an app-loader
// / UIKit launch problem from SwiftUI runtime or manager initialization failures.
@UIApplicationMain
final class ModHWManagerAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "mod_hw 管理器"
        title.font = .boldSystemFont(ofSize: 30)
        title.textAlignment = .center

        let detail = UILabel()
        detail.text = "UIKit 启动诊断页 · Build 11\n设备：\(UIDevice.current.model)\niOS：\(UIDevice.current.systemVersion)\n若此页面可见，说明应用已通过系统加载并完成 UIKit 启动。"
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .center
        detail.numberOfLines = 0

        let button = UIButton(type: .system)
        button.setTitle("进入完整管理器", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 15, left: 24, bottom: 15, right: 24)
        button.addTarget(self, action: #selector(enterFullManager), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, detail, button])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
        ])

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        if ProcessInfo.processInfo.arguments.contains("--idevelab-ci-full-manager") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.enterFullManager()
            }
        }
        return true
    }

    @objc private func enterFullManager() {
        let store = ProfileStore()
        let manager = ContentView().environmentObject(store)
        window?.rootViewController = UIHostingController(rootView: manager)
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
    @State private var appInventoryStatus = "尚未读取应用清单"
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
    @State private var recordFilter = "全部"

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
                    ? "分应用配置文件已导出：\(url.lastPathComponent)"
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

    private var managerBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.075, blue: 0.19),
                Color(red: 0.035, green: 0.16, blue: 0.36),
                Color(red: 0.055, green: 0.29, blue: 0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func managerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    private func maintenanceHero(title: String, subtitle: String, symbol: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.title2.bold()).foregroundStyle(.white)
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent, accent.opacity(0.62), Color(red: 0.06, green: 0.31, blue: 0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: accent.opacity(0.28), radius: 16, y: 7)
    }

    private var homePage: some View {
        ZStack {
            managerBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("设备管理中心")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("iOS 设备管理中心")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.84))
                        }
                        Spacer(minLength: 0)
                        Text("越狱版")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.72))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)

                    managerCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 29))
                                    .foregroundStyle(.blue)
                                    .frame(width: 54, height: 54)
                                    .background(Color.blue.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(deviceSummary?.productType ?? "正在读取设备")
                                        .font(.headline)
                                    Text("iOS \(deviceSummary?.osVersion ?? "—")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    checkCore(); fetchInstalledApps(); fetchSystemSummary()
                                    fetchMaintenanceTools(); fetchAppProfiles(); fetchBackups(); checkMaintenanceHelper()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                        .padding(10)
                                        .background(Color.blue.opacity(0.09))
                                        .clipShape(Circle())
                                }
                            }
                            HStack {
                                Label("可用空间", systemImage: "internaldrive")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(deviceSummary.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.diskFreeBytes), countStyle: .file) } ?? "读取中")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Divider()
                            HStack(spacing: 8) {
                                statusPill(helperPaired ? "权限助手已配对" : "权限助手待配对", ok: helperPaired)
                                statusPill(coreStatus.contains("已连接") ? "Core 已连接" : "Core 待检测", ok: coreStatus.contains("已连接"))
                            }
                            HStack {
                                Text("已读取应用")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(installedApps.isEmpty ? "尚未读取" : "\(installedApps.count) 个")
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                        }
                    }

                    HStack {
                        Text("功能中心").font(.title3.bold()).foregroundStyle(.white)
                        Spacer()
                        Text("快捷入口").font(.caption).foregroundStyle(.white.opacity(0.72))
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        dashboardTile("备份中心", detail: "应用数据与配置备份", icon: "externaldrive.fill", color: .blue) { backupCenterPage }
                        dashboardTile("还原中心", detail: "校验备份并安全还原", icon: "arrow.counterclockwise.circle.fill", color: .green) { restoreCenterPage }
                        dashboardTile("清理中心", detail: "指定应用本地数据清理", icon: "sparkles", color: .purple) { cleanupPage }
                        dashboardTile("改机管理", detail: "全局设备参数配置", icon: "slider.horizontal.3", color: .orange) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            ).environmentObject(profileStore)
                        }
                        dashboardTile("分应用改机", detail: "按 Bundle ID 独立配置", icon: "square.grid.2x2.fill", color: .teal) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            ).environmentObject(profileStore)
                        }
                        dashboardTile("模板管理", detail: "配置模板与导入导出", icon: "shippingbox.fill", color: .indigo) {
                            ProfileManagerView(
                                availableApps: installedApps.map { ProfileAppOption(name: $0.name, bundleIdentifier: $0.bundleIdentifier) },
                                onOperation: { action, success, detail in
                                    recordOperation(action, target: "Hook 配置", success: success, detail: detail)
                                }
                            ).environmentObject(profileStore)
                        }
                    }

                    Text("快捷操作").font(.title3.bold()).foregroundStyle(.white)
                    VStack(spacing: 0) {
                        NavigationLink { diagnosticsPage } label: {
                            featureRow("系统诊断", detail: "Core、Hook、权限与维护工具状态", icon: "stethoscope")
                        }
                        Divider().padding(.leading, 48)
                        NavigationLink { IPAEditorView() } label: {
                            featureRow("IPA 多开", detail: "打开原作者 IPA 编辑器", icon: "square.stack.3d.up.fill")
                        }
                        Divider().padding(.leading, 48)
                        NavigationLink { recordsPage } label: {
                            featureRow("操作记录", detail: "查看备份、还原、清理和改机记录", icon: "clock.arrow.circlepath")
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.white.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Text("维护操作由已配对的 Root Helper 执行；Core 仅提供只读设备信息。清理和还原均保留备份或回滚快照。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 2)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func statusPill(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ok ? Color.green : Color.orange)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background((ok ? Color.green : Color.orange).opacity(0.10))
            .clipShape(Capsule())
    }

    private func dashboardTile<Destination: View>(_ title: String, detail: String, icon: String, color: Color, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 46, height: 46)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(Color.white.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

        private var backupCenterPage: some View {
        ZStack {
            managerBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    maintenanceHero(title: "一键备份", subtitle: "应用本地数据与 Hook 配置备份", symbol: "externaldrive.fill", accent: .blue)
                    managerCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("备份内容").font(.headline)
                            Label("指定应用本地数据容器", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                            Label("全局与分应用 Hook 配置", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                            Text("备份包含 SHA-256 清单。Keychain、App Groups、共享容器和服务端数据不在本备份范围内。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Divider()
                            appTargetPicker
                            Button(maintenanceRunning ? "正在备份…" : "开始备份") { performMaintenance("backup") }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                            Button("备份全局与分应用 Hook 配置") { performMaintenance("config-backup") }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .disabled(!helperPaired || maintenanceRunning)
                        }
                    }
                    managerCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("备份记录").font(.headline)
                                Spacer()
                                Text("共 \(backups.count) 条").font(.caption).foregroundStyle(.secondary)
                                Button("刷新") { fetchBackups() }.font(.caption)
                            }
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
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 7)
                                    if backup.id != backups.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    if !maintenanceResult.isEmpty {
                        managerCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("执行结果").font(.headline)
                                Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("备份中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

        private var restoreCenterPage: some View {
        ZStack {
            managerBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    maintenanceHero(title: "一键还原", subtitle: "先校验备份，再安全恢复应用数据与配置", symbol: "arrow.counterclockwise", accent: .cyan)
                    managerCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("选择备份文件").font(.headline)
                            appTargetPicker
                            TextField("备份文件名", text: $maintenanceArchiveName)
                                .font(.footnote.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("验证备份完整性") { performMaintenance("verify") }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .disabled(!helperPaired || maintenanceRunning || maintenanceArchiveName.isEmpty)
                            Button("开始还原") {
                                pendingMaintenanceAction = "restore"
                                showMaintenanceConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty || maintenanceArchiveName.isEmpty)
                            Text("还原前会再次验证备份，并创建当前应用容器回滚快照。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    managerCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("全局与分应用配置").font(.headline)
                            Text("校验配置归档 SHA-256 与内部路径，并保留还原前快照。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("还原最近一次 Hook 配置备份") {
                                pendingMaintenanceAction = "config-restore"
                                showMaintenanceConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!helperPaired || maintenanceRunning)
                        }
                    }
                    managerCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("可用应用数据备份").font(.headline)
                            if backups.isEmpty {
                                Text(backupsStatus).font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ForEach(backups.filter { maintenanceBundleID.isEmpty || $0.bundleIdentifier == maintenanceBundleID }) { backup in
                                    Button {
                                        maintenanceBundleID = backup.bundleIdentifier
                                        maintenanceArchiveName = backup.archive
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "externaldrive.fill").foregroundStyle(.blue)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(backup.bundleIdentifier).font(.subheadline.weight(.semibold))
                                                Text(backup.archive).font(.caption.monospaced())
                                                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: backup.sizeBytes), countStyle: .file))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                        }
                                        .foregroundStyle(.primary)
                                    }
                                    Divider()
                                }
                            }
                            Button("刷新备份列表") { fetchBackups() }.font(.caption)
                        }
                    }
                    if !maintenanceResult.isEmpty {
                        managerCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("执行结果").font(.headline)
                                Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog("确认执行配置还原", isPresented: $showMaintenanceConfirmation, titleVisibility: .visible) {
            if pendingMaintenanceAction == "restore" {
                Button("确认还原应用数据", role: .destructive) { performMaintenance("restore") }
            } else if pendingMaintenanceAction == "config-restore" {
                Button("确认还原全局与分应用配置", role: .destructive) { performMaintenance("config-restore") }
            }
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text(pendingMaintenanceAction == "config-restore"
                 ? "将恢复最近一次全局与分应用 Hook 配置备份，并保留还原前快照。"
                 : "还原前会再次验证备份，并创建当前应用容器回滚快照。")
        }
        .navigationTitle("还原中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

        private var cleanupPage: some View {
        ZStack {
            managerBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    maintenanceHero(title: "深度清理", subtitle: "清理指定应用的本地数据容器", symbol: "sparkles", accent: .purple)
                    managerCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("清理目标").font(.headline)
                            appTargetPicker
                            Label("清理 Documents、Library、Caches 等容器内容", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                            Label("清理前自动备份并校验 SHA-256", systemImage: "checkmark.shield.fill").foregroundStyle(.blue)
                            Label("失败时从清理前快照自动回滚", systemImage: "arrow.uturn.backward.circle.fill").foregroundStyle(.blue)
                            Divider()
                            Text("Keychain 将在目标 App 下次启动时清理其私有 application-identifier 访问组的本机条目；共享 Keychain 组、iCloud 同步条目、App Groups、共享容器及服务端数据仍不清理。此功能不能等同于刷机。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button(maintenanceRunning ? "正在清理…" : "立即清理") {
                                pendingMaintenanceAction = "clean"
                                showMaintenanceConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .frame(maxWidth: .infinity)
                            .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                            Button("检查 Keychain 清理结果") { checkKeychainCleanupStatus() }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                        }
                    }
                    if !maintenanceResult.isEmpty {
                        managerCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("执行结果").font(.headline)
                                Text(maintenanceResult).font(.footnote.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog("确认深度清理指定应用", isPresented: $showMaintenanceConfirmation, titleVisibility: .visible) {
            Button("确认清理并自动备份", role: .destructive) { performMaintenance("clean") }
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text("此操作将清空所选应用的本地数据容器，并在目标 App 下次启动时删除其私有 Keychain 访问组中的本机条目。Keychain 不包含在本地备份内，删除后无法通过本工具还原；共享组和 iCloud 同步条目不会删除。请先完全退出目标应用。")
        }
        .navigationTitle("清理中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

        private var appTargetPicker: some View {
        Group {
            if !installedApps.isEmpty {
                Picker("选择目标应用", selection: $maintenanceBundleID) {
                    Text("请选择").tag("")
                    ForEach(installedApps) { app in
                        Text(app.name).tag(app.bundleIdentifier)
                    }
                }
            } else {
                TextField("应用标识（Bundle ID）", text: $maintenanceBundleID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
    }

    private var filteredOperationRecords: [MaintenanceRecord] {
        operationRecords.filter { record in
            let action = record.action.lowercased()
            switch recordFilter {
            case "备份": return action.contains("backup") || action.contains("备份")
            case "还原": return action.contains("restore") || action.contains("还原")
            case "清理": return action.contains("clean") || action.contains("清理")
            case "改机": return action.contains("profile") || action.contains("配置") || action.contains("改机")
            default: return true
            }
        }
    }

    private var recordsPage: some View {
        ZStack {
            managerBackground.ignoresSafeArea()
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("操作记录").font(.title3.bold())
                        Text("共 \(operationRecords.count) 条记录").font(.caption).foregroundStyle(.secondary)
                        Picker("记录类型", selection: $recordFilter) {
                            ForEach(["全部", "备份", "还原", "清理", "改机"], id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 5)
                }
                if filteredOperationRecords.isEmpty {
                    Section {
                        VStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                            Text("暂无操作记录").font(.headline)
                            Text("备份、还原、清理和改机操作完成后会显示在这里。")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section {
                        ForEach(filteredOperationRecords) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.action).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    let hookWritePending = record.action.contains("Hook 配置应用")
                                    Label(hookWritePending ? "已写入，待验证" : (record.success ? "成功" : "失败"),
                                          systemImage: hookWritePending ? "clock.badge.exclamationmark" : (record.success ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                        .font(.caption)
                                        .foregroundStyle(hookWritePending ? .orange : (record.success ? .green : .red))
                                }
                                Text(record.target).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(record.date.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                if !record.detail.isEmpty {
                                    Text(record.detail).font(.caption).lineLimit(4).textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 6)
                            .listRowBackground(Color.white.opacity(0.96))
                        }
                    }
                }
                Section {
                    Button("刷新记录") { loadOperationRecords() }
                    Button("清空操作记录", role: .destructive) {
                        operationRecords = []
                        UserDefaults.standard.removeObject(forKey: "iDeviceLabMaintenanceRecordsV1")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("操作记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                Button("直接配对权限助手") { pairMaintenanceHelper() }
                    .disabled(maintenanceRunning)
                Text("由 Root Helper 验证当前 Manager 的 Bundle ID 和代码签名后自动配对，不需要终端或输入 root 密码。管理器更新后若签名变化，可在此重新配对。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("维护与验收") {
                NavigationLink("高级维护与 iPhone 12 最终验收") { maintenancePage }
            }
            Section("配置文件") {
                LabeledContent("当前导入文件", value: fileName)
                LabeledContent("配置解析", value: importedData == nil ? "未导入" : (isValid ? "有效" : "无效"))
                NavigationLink("打开设备配置管理") { profilesPage }
                NavigationLink("打开分应用环境管理") {
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
                    LabeledContent("运行模式", value: "无根模式（Rootless）")
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
                Label("分应用配置管理", systemImage: "slider.horizontal.3").font(.title2.bold())
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
            Section("目标应用") {
                HStack {
                    Text("已读取应用")
                    Spacer()
                    Text("\(installedApps.count)").foregroundStyle(.secondary)
                }
                if installedApps.isEmpty {
                    Text("请先在诊断页连接 Alpha11 Core 并读取应用清单。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("配置目标", selection: $selectedProfileBundleID) {
                        ForEach(installedApps) { app in
                            Text("\(app.name) · \(app.bundleIdentifier)").tag(app.bundleIdentifier)
                        }
                    }
                    Button("导出为所选应用的独立配置") {
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
                Text("此清单只读取文件名和 plist 格式，不显示配置字段值，也不代表目标应用已加载该配置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("配置文件应用方式") {
                Text("管理器当前负责生成独立配置；Core 可读取越狱端已安装配置清单。将导出的 plist 放入上方目录后，目标应用下次启动时由原作者 Hook 按 Bundle ID 选择配置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("操作结果") { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("配置管理")
    }

    private var maintenancePage: some View {
        List {
            Section {
                Label("应用数据维护", systemImage: "externaldrive.fill").font(.title2.bold())
                Text("管理器通过独立 Root Helper 执行固定白名单操作；Core 继续保持只读。首次安装或管理器更新后，在此页面点击配对即可。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Root 权限助手") {
                LabeledContent("连接状态", value: helperStatus)
                Button("重新检测权限助手") { checkMaintenanceHelper() }
                Button("直接配对 / 更新后重新配对") { pairMaintenanceHelper() }
                    .disabled(maintenanceRunning)
                Text("由 Root Helper 验证当前 Manager 的 Bundle ID 和代码签名后自动配对，不需要终端或输入 root 密码。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("目标应用") {
                if !installedApps.isEmpty {
                    Picker("已安装应用", selection: $maintenanceBundleID) {
                        Text("选择应用").tag("")
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.bundleIdentifier)
                        }
                    }
                }
                TextField("Bundle ID（例如 com.example.app）", text: $maintenanceBundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("刷新应用清单") { fetchInstalledApps() }
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
                Button(maintenanceRunning ? "正在执行…" : "直接备份所选应用") { performMaintenance("backup") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(maintenanceRunning ? "正在执行…" : "直接验证备份完整性") { performMaintenance("verify") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceArchiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("还原与清理") {
                Button("还原指定应用") {
                    pendingMaintenanceAction = "restore"
                    showMaintenanceConfirmation = true
                }
                .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty || maintenanceArchiveName.isEmpty)
                Button("清理指定应用") {
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
                Button("诊断所选应用的 Keychain 权限声明") { performMaintenance("keychain-diagnose") }
                    .disabled(!helperPaired || maintenanceRunning || maintenanceBundleID.isEmpty)
                Button("检查所选应用的 Keychain 清理结果") { checkKeychainCleanupStatus() }
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
            Button("确认还原应用", role: .destructive) { performMaintenance("restore") }
                .disabled(pendingMaintenanceAction != "restore")
            Button("确认清理应用", role: .destructive) { performMaintenance("clean") }
                .disabled(pendingMaintenanceAction != "clean")
            Button("确认还原配置", role: .destructive) { performMaintenance("config-restore") }
                .disabled(pendingMaintenanceAction != "config-restore")
            Button("取消", role: .cancel) { pendingMaintenanceAction = nil }
        } message: {
            Text("此操作会改变所选应用或配置数据。请确认目标和备份状态无误。")
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
            Section("应用清单") {
                LabeledContent("读取状态", value: appInventoryStatus)
                LabeledContent("已读取数量", value: "\(installedApps.count)")
                Button(appsLoading ? "读取中…" : "重新读取应用清单") { fetchInstalledApps() }
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
                Button("直接诊断所选应用的 Keychain 权限声明") { performMaintenance("keychain-diagnose") }
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
            "backup": "应用数据备份", "verify": "备份完整性校验",
            "restore": "应用数据还原", "clean": "应用深度清理",
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

    private func pairMaintenanceHelper() {
        maintenanceRunning = true
        helperStatus = "正在验证 Manager 并配对…"
        Task {
            defer { maintenanceRunning = false }
            do {
                let result = try await MaintenanceClient.request(action: "pair")
                helperPaired = result.ok && result.paired == true
                helperStatus = helperPaired ? "已配对，可直接执行" : (result.error ?? "配对失败")
                maintenanceResult = result.output ?? result.error ?? (helperPaired ? "权限助手配对成功。" : "权限助手配对失败。")
            } catch {
                helperPaired = false
                helperStatus = "配对失败：\(error.localizedDescription)"
                maintenanceResult = helperStatus
            }
        }
    }



    private func performMaintenance(_ action: String) {
        let bundleID = maintenanceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let archive = maintenanceArchiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["backup", "restore", "clean", "keychain-diagnose"].contains(action) && bundleID.isEmpty {
            maintenanceResult = "请先选择或填写目标应用的 Bundle ID。"
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
                let outputText = (result.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let errorText = (result.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var detailParts: [String] = []
                if !errorText.isEmpty { detailParts.append(errorText) }
                if !outputText.isEmpty { detailParts.append(outputText) }
                if detailParts.isEmpty {
                    detailParts.append("Root Helper 返回退出码：\(result.exitCode ?? -1)，但没有提供标准输出或错误输出。")
                }
                let detail = detailParts.joined(separator: "\n")
                maintenanceResult = result.ok ? detail : "操作失败：\n\(detail)"
                if action == "clean" && result.ok {
                    maintenanceResult += "\n\n钥匙串清理任务已排队。请打开目标 App 一次，返回管理器后点击“检查 Keychain 清理结果”。"
                }
                recordOperation(action, target: bundleID.isEmpty ? archive : bundleID, success: result.ok, detail: detail)
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

    private func checkKeychainCleanupStatus() {
        let bundleID = maintenanceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else {
            maintenanceResult = "请先选择或填写目标应用的 Bundle ID。"
            return
        }
        maintenanceRunning = true
        Task {
            defer { maintenanceRunning = false }
            do {
                let result = try await MaintenanceClient.request(action: "keychain-clean-status", bundleID: bundleID)
                let detail = result.output ?? result.error ?? "Root Helper 未返回详细结果。"
                if result.pending == true {
                    maintenanceResult = "Keychain 清理尚未执行：请打开目标 App 一次，再返回此页检查。\n\(detail)"
                } else {
                    maintenanceResult = result.ok ? "Keychain 清理完成：\n\(detail)" : "Keychain 清理失败：\n\(detail)"
                }
                recordOperation("keychain-clean-status", target: bundleID,
                                success: result.ok && result.pending != true, detail: detail)
            } catch {
                maintenanceResult = "读取 Keychain 清理状态失败：\(error.localizedDescription)"
                recordOperation("keychain-clean-status", target: bundleID, success: false,
                                detail: error.localizedDescription)
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
                      payload["mode"] as? String == "sandboxed-app-group-bridge" else {
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
        appInventoryStatus = "正在读取本机应用清单…"
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
                    appInventoryStatus = "Core 返回的应用清单格式无效"
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
                appInventoryStatus = "已读取 \(installedApps.count) 个应用（只读清单）"
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
                profilesStatus = "已读取 \(appProfiles.count) 个分应用配置"
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
                status = "导入成功（\(format == .binary ? "二进制" : "XML") plist）。已读取字段名称和类型；字段值未展示，导出保留原始字节。"
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
        if value is String { return "字符串" }
        if value is Data { return "数据" }
        if value is Date { return "日期" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "布尔值" : "数字"
        }
        if value is [String: Any] { return "字典" }
        if value is [Any] { return "数组" }
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
    let pending: Bool?
}

enum MaintenanceClient {
    private static let bridgeURL = URL(string: "http://127.0.0.1:18081/maintenance")!
    private static let bridgeTokenName = "idevelab-manager-bridge.token"

    // The explicitly entitled App Group is shared with the mobile Core.
    // The ordinary app sandbox cannot read another app's private container.
    private static let managerAppGroupIdentifier = "group.com.idevelab.manager"

    private static func managerGroupContainerURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: managerAppGroupIdentifier) else {
            throw NSError(domain: "MaintenanceHelper", code: 7, userInfo: [NSLocalizedDescriptionKey: "无法定位 Manager 共享通信目录，请通过 TrollStore 重新安装 Build19。"])
        }
        return container.standardizedFileURL
    }

    private static func bridgeToken() throws -> String {
        let fileManager = FileManager.default
        let support = try managerGroupContainerURL().appendingPathComponent("Library/Application Support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tokenURL = support.appendingPathComponent(bridgeTokenName, isDirectory: false)
        var tokenData: Data
        if fileManager.fileExists(atPath: tokenURL.path) {
            tokenData = try Data(contentsOf: tokenURL, options: [.mappedIfSafe])
        } else {
            var random = Data(count: 32)
            let result = random.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
            }
            guard result == errSecSuccess else {
                throw NSError(domain: "MaintenanceHelper", code: 8, userInfo: [NSLocalizedDescriptionKey: "无法生成 Core 通信凭据。"])
            }
            let hexToken = random.map { String(format: "%02x", $0) }.joined()
            tokenData = Data(hexToken.utf8)
            try tokenData.write(to: tokenURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        }
        guard tokenData.count == 64,
              String(data: tokenData, encoding: .ascii)?.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) == true else {
            throw NSError(domain: "MaintenanceHelper", code: 9, userInfo: [NSLocalizedDescriptionKey: "Manager 通信凭据文件无效，请重新启动管理器。"])
        }
        return String(decoding: tokenData, as: UTF8.self)
    }

    static func request(action: String, bundleID: String? = nil, archive: String? = nil, profile: [String: Any]? = nil, confirm: Bool = false) async throws -> MaintenanceOperationResult {
        var payload: [String: Any] = ["action": action, "managerPID": Int(getpid()), "managerGroupContainer": try managerGroupContainerURL().path]
        if let bundleID { payload["bundleID"] = bundleID }
        if let archive { payload["archive"] = archive }
        if let profile { payload["profile"] = profile }
        if confirm { payload["confirm"] = true }
        let requestData = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: requestData, encoding: .utf8) else {
            throw NSError(domain: "MaintenanceHelper", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法编码维护请求。"])
        }
        var components = URLComponents(url: bridgeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "request", value: json)]
        guard let url = components.url else {
            throw NSError(domain: "MaintenanceHelper", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法生成 Core 通信地址。"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(try bridgeToken(), forHTTPHeaderField: "X-iDeviceLab-Manager-Token")
        request.timeoutInterval = 300
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "MaintenanceHelper", code: 6, userInfo: [NSLocalizedDescriptionKey: "Core 通信桥返回异常响应。"])
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF8 response>"
            throw NSError(domain: "MaintenanceHelper", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Core 返回内容不是有效 JSON：\(error.localizedDescription)。响应片段：\(body)"
            ])
        }
        guard let payload = object as? [String: Any], let ok = payload["ok"] as? Bool else {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF8 response>"
            throw NSError(domain: "MaintenanceHelper", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Core 响应缺少有效的 ok 字段或不是对象。响应片段：\(body)"
            ])
        }
        func stringValue(_ key: String) -> String? {
            guard let value = payload[key], !(value is NSNull) else { return nil }
            return value as? String
        }
        func intValue(_ key: String) -> Int? {
            guard let number = payload[key] as? NSNumber else { return nil }
            return number.intValue
        }
        func boolValue(_ key: String) -> Bool? {
            guard let number = payload[key] as? NSNumber else { return nil }
            return number.boolValue
        }
        return MaintenanceOperationResult(
            ok: ok, paired: boolValue("paired"), helper: stringValue("helper"),
            action: stringValue("action"), exitCode: intValue("exitCode"),
            output: stringValue("output"), error: stringValue("error"),
            outputTruncated: boolValue("outputTruncated"), pending: boolValue("pending")
        )
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
