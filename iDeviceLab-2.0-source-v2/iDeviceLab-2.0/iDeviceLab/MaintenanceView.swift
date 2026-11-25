import SwiftUI
import UniformTypeIdentifiers

/// Backup/restore and conservative cleanup for iDeviceLab's own sandbox.
/// This view intentionally does not delete another app's container or system data.
struct MaintenanceView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var backupURL: URL?
    @State private var showingImporter = false
    @State private var cacheBytes: Int64 = 0
    @State private var temporaryBytes: Int64 = 0
    @State private var message: String?
    @State private var isWorking = false
    @State private var confirmCleanup = false

    private var totalBytes: Int64 { cacheBytes + temporaryBytes }

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

                Section("范围说明") {
                    Text("完整备份包含本应用保存的配置、分 App 绑定关系和当前选中项。它不是整机备份，也不包含其他 App 的私有数据。")
                    Text("清理功能仅清理本应用缓存和临时文件。越狱环境下其他 App 容器的清理需要独立的授权、路径校验、预览和确认流程，不会在此处进行无差别删除。")
                }
            }
            .navigationTitle("备份与维护")
            .onAppear { scan() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .data]) { result in
                importBackup(result)
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
