import SwiftUI
import UIKit
import Darwin

private struct DeviceDiagnosticReport: Codable {
    let generatedAt: Date
    let deviceModel: String
    let hardwareIdentifier: String
    let systemVersion: String
    let architecture: String
    let jailbreakRootlessDetected: Bool
    let availableStorageBytes: Int64?
    let totalStorageBytes: Int64?
}

struct CompatibilityView: View {
    @State private var reportURL: URL?
    @State private var reportMessage: String?

    private var systemVersion: String { UIDevice.current.systemVersion }
    private var hardware: String { Self.hardwareIdentifier() }
    private var isRootlessPresent: Bool {
        FileManager.default.fileExists(atPath: "/var/jb") ||
        FileManager.default.fileExists(atPath: "/private/preboot")
    }
    private var storage: (free: Int64?, total: Int64?) {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) else {
            return (nil, nil)
        }
        return (values[.systemFreeSize] as? Int64, values[.systemSize] as? Int64)
    }
    private var versionStatus: String {
        if systemVersion == "16.2" { return "目标版本：iOS 16.2" }
        if systemVersion.hasPrefix("16.") { return "iOS 16 系列：需按实际小版本验证" }
        return "当前版本与目标版本不同：需要重新验证兼容性"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("设备识别") {
                    LabeledContent("设备型号", value: UIDevice.current.model)
                    LabeledContent("硬件标识", value: hardware)
                    LabeledContent("系统版本", value: systemVersion)
                    LabeledContent("处理器架构", value: Self.architecture())
                }

                Section("iOS 16.2 适配检查") {
                    Label(versionStatus, systemImage: systemVersion == "16.2" ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(systemVersion == "16.2" ? .green : .orange)
                    LabeledContent("Rootless 路径", value: isRootlessPresent ? "检测到相关目录" : "未检测到 /var/jb")
                    Text("目录存在只代表检测到相关路径，不等于已确认越狱工具、注入框架或后台服务正常。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("存储状态") {
                    if let free = storage.free, let total = storage.total {
                        LabeledContent("可用空间", value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                        LabeledContent("总空间", value: ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    } else {
                        Text("系统未提供存储容量信息")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("诊断报告") {
                    Button {
                        exportReport()
                    } label: {
                        Label("生成设备诊断报告", systemImage: "doc.text")
                    }
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("分享 / 保存诊断报告", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let reportMessage {
                        Text(reportMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("此页面仅读取设备公开系统信息和路径存在状态，不修改设备标识、不清除其他应用数据，也不代表已完成真机兼容性测试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设备诊断")
        }
    }

    private func exportReport() {
        let values = storage
        let report = DeviceDiagnosticReport(
            generatedAt: Date(),
            deviceModel: UIDevice.current.model,
            hardwareIdentifier: hardware,
            systemVersion: systemVersion,
            architecture: Self.architecture(),
            jailbreakRootlessDetected: isRootlessPresent,
            availableStorageBytes: values.free,
            totalStorageBytes: values.total
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("iDeviceLab-Diagnostic.json")
            try data.write(to: url, options: .atomic)
            reportURL = url
            reportMessage = "报告已生成，可通过分享菜单保存"
        } catch {
            reportMessage = "生成失败：\(error.localizedDescription)"
        }
    }

    private static func architecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.machine)) {
                String(cString: $0)
            }
        }
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return "未知"
        }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return "未知"
        }
        return String(cString: machine)
    }
}
