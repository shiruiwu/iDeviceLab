import SwiftUI
import UniformTypeIdentifiers

/// Backup/restore and conservative cleanup for iDeviceLab's own sandbox.
/// This view intentionally does not delete another app's container or system data.
struct MaintenanceView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var backupURL: URL?
    @State private var reportURL: URL?
    @State private var showingImporter = false
    @State private var cacheBytes: Int64 = 0
    @State private var temporaryBytes: Int64 = 0
    @State private var message: String?
    @State private var isWorking = false
    @State private var confirmCleanup = false
    @State private var confirmAppCleanup = false
    @State private var appItems: [AppMaintenanceItem] = []
    @State private var selectedAppBundleID = ""
    @State private var orphanedContainerCount = 0
    @State private var orphanedContainers: [OrphanedContainerItem] = []
    @State private var inventoryScannedAt: Date?
    @State private var lastAppCleanup: [String: Any]?
    @State private var appMaintenanceMessage = "尚未扫描"
    @State private var isCleaningApp = false

    private let coreURL = URL(string: "http://127.0.0.1:18080")!
    private var totalBytes: Int64 { cacheBytes + temporaryBytes }
    private var selectedApp: AppMaintenanceItem? { appItems.first { $0.bundleIdentifier == selectedAppBundleID } }
    private var selectedAppDisplayName: String { selectedApp?.name ?? "所选应用" }

    var body: some View {
        NavigationStack {
            List {
                Section("完整配置备份") {
                    LabeledContent("配置数量", value: "\(store.profiles.count)")
                    LabeledContent("应用绑定", value: "\(store.managedApps.count)")
                    Button { makeBackup() } label: {
                        Label("生成完整备份", systemImage: "archivebox")
                    }
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("分享 / 保存备份文件", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { exportMaintenanceReport() } label: {
                        Label("生成维护诊断报告", systemImage: "doc.text.magnifyingglass")
                    }
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("分享 / 保存诊断报告", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { showingImporter = true } label: {
                        Label("从备份文件还原", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) { restoreRollback() } label: {
                        Label("撤销上次还原", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section("本应用空间清理") {
                    LabeledContent("缓存目录", value: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                    LabeledContent("临时文件", value: ByteCountFormatter.string(fromByteCount: temporaryBytes, countStyle: .file))
                    LabeledContent("可清理总量", value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    Button { scan() } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { confirmCleanup = true } label: {
                        Label("清理本应用缓存和临时文件", systemImage: "trash")
                    }
                    .disabled(isWorking || totalBytes == 0)
                    Text("只处理 iDeviceLab 自己沙盒内的 Caches 和 tmp，不触碰其他 App 的数据、登录状态或系统目录。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("指定 App 本地缓存维护") {
                    HStack {
                        Text("扫描状态")
                        Spacer()
                        Text(appMaintenanceMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if !appItems.isEmpty {
                        Picker("选择应用", selection: $selectedAppBundleID) {
                            ForEach(appItems) { app in
                                Text("\(app.name) · \(app.bundleIdentifier)").tag(app.bundleIdentifier)
                            }
                        }
                        if let app = selectedApp {
                            LabeledContent("应用容器", value: app.containerAvailable ? "可访问" : "不可访问")
                            LabeledContent("Caches", value: ByteCountFormatter.string(fromByteCount: Int64(app.cachesBytes), countStyle: .file))
                            LabeledContent("tmp", value: ByteCountFormatter.string(fromByteCount: Int64(app.temporaryBytes), countStyle: .file))
                            LabeledContent("预计可清理", value: ByteCountFormatter.string(fromByteCount: Int64(app.cleanableBytes), countStyle: .file))
                            Button { Task { await refreshAppInventory() } } label: {
                                Label("重新扫描应用数据", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) { confirmAppCleanup = true } label: {
                                Label("清理所选 App 缓存和临时文件", systemImage: "trash")
                            }
                            .disabled(isCleaningApp || !app.containerAvailable || app.cleanableBytes == 0)
                        }
                    } else {
                        Text("尚未发现可维护的应用容器，或 Rootless 核心没有读取权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("疑似卸载残留容器", value: "\(orphanedContainerCount) 个")
                    if let inventoryScannedAt {
                        LabeledContent("最近扫描", value: inventoryScannedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !orphanedContainers.isEmpty {
                        ForEach(orphanedContainers) { orphan in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(orphan.bundleIdentifier).font(.subheadline)
                                Text("容器 UUID：\(orphan.containerUUID)")
                                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                Text("\(orphan.accessible ? "可访问" : "不可访问") · \(ByteCountFormatter.string(fromByteCount: orphan.containerBytes, countStyle: .file))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("仅清理所选已安装 App 容器内的 Library/Caches 和 tmp。疑似残留只列出供核查，不会自动删除。不会删除 Documents、数据库、偏好设置、钥匙串或登录凭据。清理前请先退出目标 App。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("范围说明") {
                    Text("完整备份包含本应用保存的配置、分 App 绑定关系和当前选中项。它不是整机备份，也不包含其他 App 的私有数据。")
                    Text("清理功能仅清理本应用缓存和临时文件。越狱环境下其他 App 容器的清理需要独立的授权、路径校验、预览和确认流程，不会在此处进行无差别删除。")
                }
            }
            .navigationTitle("备份与维护")
            .onAppear { scan(); Task { await refreshAppInventory() } }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .data]) { result in
                importBackup(result)
            }
            .confirmationDialog("确认清理所选 App 缓存？", isPresented: $confirmAppCleanup, titleVisibility: .visible) {
                Button("清理所选 App 的 Caches 和 tmp", role: .destructive) { Task { await clearSelectedAppCaches() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只清理 \(selectedApp?.name ?? "所选应用") 的 Library/Caches 和 tmp。请先退出该应用；文档、数据库、偏好设置和凭据不会被删除。")
            }
            .confirmationDialog("确认清理本应用缓存？", isPresented: $confirmCleanup, titleVisibility: .visible) {
                Button("清理缓存和临时文件", role: .destructive) { clearOwnedTemporaryFiles() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只删除 iDeviceLab 自身 Caches 和 tmp 目录内容，不会删除配置、备份文件或其他 App 数据。")
            }
            .alert("iDeviceLab", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    @MainActor
    private func refreshAppInventory() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: coreURL.appendingPathComponent("maintenance/apps"))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(AppMaintenanceResponse.self, from: data)
            guard result.ok else { throw URLError(.cannotParseResponse) }
            appItems = result.apps
            orphanedContainerCount = result.orphanedContainerCount
            orphanedContainers = result.orphanedContainers ?? []
            inventoryScannedAt = Date()
            if !appItems.contains(where: { $0.bundleIdentifier == selectedAppBundleID }) {
                selectedAppBundleID = appItems.first?.bundleIdentifier ?? ""
            }
            appMaintenanceMessage = "已扫描 \(appItems.count) 个已安装应用"
        } catch {
            appMaintenanceMessage = "扫描失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearSelectedAppCaches() async {
        guard let app = selectedApp, app.containerAvailable, !isCleaningApp else { return }
        isCleaningApp = true
        defer { isCleaningApp = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["bundleIdentifier": app.bundleIdentifier])
            var request = URLRequest(url: coreURL.appendingPathComponent("maintenance/clear"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  object?["ok"] as? Bool == true else {
                throw NSError(domain: "iDeviceLab.AppMaintenance", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: object?["error"] as? String ?? "核心拒绝清理"])
            }
            let removed = (object?["removedBytes"] as? NSNumber)?.int64Value ?? 0
            lastAppCleanup = [
                "bundleIdentifier": app.bundleIdentifier,
                "appName": app.name,
                "removedBytes": removed,
                "completedAt": ISO8601DateFormatter().string(from: Date()),
                "areas": ["Library/Caches", "tmp"]
            ]
            appMaintenanceMessage = "清理完成：\(ByteCountFormatter.string(fromByteCount: removed, countStyle: .file))"
            await refreshAppInventory()
            message = "已清理 \(app.name) 的缓存和临时文件。没有删除应用文档、数据库、偏好设置或凭据。"
        } catch {
            message = "App 缓存清理失败：\(error.localizedDescription)"
            await refreshAppInventory()
        }
    }

    private func exportMaintenanceReport() {
        scan()
        let appInventory = appItems.map { app in
            [
                "name": app.name,
                "bundleIdentifier": app.bundleIdentifier,
                "version": app.version,
                "containerAvailable": app.containerAvailable,
                "cachesBytes": app.cachesBytes,
                "temporaryBytes": app.temporaryBytes,
                "cleanableBytes": app.cleanableBytes
            ] as [String: Any]
        }
        let orphanInventory = orphanedContainers.map { item in
            [
                "bundleIdentifier": item.bundleIdentifier,
                "containerUUID": item.containerUUID,
                "accessible": item.accessible,
                "containerBytes": item.containerBytes
            ] as [String: Any]
        }
        let report: [String: Any] = [
            "reportVersion": 2,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "inventoryScannedAt": inventoryScannedAt.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
            "device": ["platform": "iOS", "app": "iDeviceLab"],
            "manager": ["profileCount": store.profiles.count, "managedAppBindingCount": store.managedApps.count],
            "appOwnedStorage": ["cachesBytes": cacheBytes, "temporaryBytes": temporaryBytes, "totalScannedBytes": totalBytes],
            "installedAppInventory": appInventory,
            "orphanedContainers": orphanInventory,
            "orphanedContainerCount": orphanedContainerCount,
            "lastAppCleanup": lastAppCleanup ?? NSNull(),
            "scope": [
                "included": ["iDeviceLab Caches", "iDeviceLab tmp", "installed app cache and tmp sizes from the last Rootless scan", "orphan container identifiers and aggregate sizes", "local profile counts"],
                "notInspected": ["app document contents", "Keychain items", "account sessions", "cloud-side state", "whole-device backup"],
                "note": "Orphan containers are diagnostic candidates only. Inventory is a point-in-time scan and does not prove that any app data or credentials were erased."
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = documents.appendingPathComponent("iDeviceLabReports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("iDeviceLab-Maintenance-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            reportURL = url
            message = "维护诊断报告已生成。报告只包含本应用空间统计和能力范围，不包含其他 App 的私有内容或凭据。"
        } catch {
            message = "生成维护报告失败：\(error.localizedDescription)"
        }
    }

    private func makeBackup() {
        do {
            let data = try store.exportFullBackupData()
            let fm = FileManager.default
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let backupDirectory = documents.appendingPathComponent("iDeviceLabBackups", isDirectory: true)
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let url = backupDirectory.appendingPathComponent("iDeviceLab-FullBackup-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            backupURL = url
            message = "完整备份已生成。请使用分享按钮保存到‘文件’或其他安全位置。"
        } catch {
            message = "备份失败：\(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try store.restoreFullBackup(from: data)
            backupURL = nil
            message = "还原成功。还原前的配置已自动保存，可使用‘撤销上次还原’恢复。"
        } catch {
            message = "还原失败，原配置未主动清除：\(error.localizedDescription)"
        }
    }

    private func restoreRollback() {
        do {
            try store.restorePreRestoreSnapshot()
            message = "已恢复到上次还原前的配置。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func scan() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporary = fm.temporaryDirectory
        cacheBytes = caches.map(directorySize) ?? 0
        temporaryBytes = directorySize(temporary)
    }

    private func directorySize(_ directory: URL) -> Int64 {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return 0 }
        return children.reduce(Int64(0)) { partial, child in
            partial + itemSize(child)
        }
    }

    private func itemSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true else { return 0 }
        if values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard values.isDirectory == true,
              let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return 0 }
        return children.reduce(Int64(0)) { $0 + itemSize($1) }
    }

    private func clearOwnedTemporaryFiles() {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let fm = FileManager.default
        let roots = [
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fm.temporaryDirectory
        ].compactMap { $0 }.map { $0.standardizedFileURL }

        do {
            for root in roots {
                // Only operate on the two known app-owned roots, and reject a redirected root.
                guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
                    throw NSError(domain: "iDeviceLab.Maintenance", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "检测到缓存目录路径异常，已停止清理。"])
                }

                let children = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isSymbolicLinkKey],
                    options: []
                )
                for child in children {
                    let candidate = child.standardizedFileURL
                    guard candidate.deletingLastPathComponent().path == root.path else {
                        throw NSError(domain: "iDeviceLab.Maintenance", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "检测到目录越界路径，已停止清理。"])
                    }
                    // FileManager removes a symlink itself rather than traversing its target.
                    try fm.removeItem(at: candidate)
                }
            }
            scan()
            message = "已清理本应用的缓存和临时文件。配置、备份及其他 App 数据未受影响。"
        } catch {
            scan()
            message = "清理过程中出现错误：\(error.localizedDescription)"
        }
    }
}
