import SwiftUI

private struct RootlessStatus: Decodable {
    let ok: Bool
    let service: String?
    let version: String?
}

private struct DeviceSystemInfo: Decodable {
    let productType: String
    let architecture: String
    let osVersion: String
    let hostname: String
    let diskTotalBytes: UInt64
    let diskFreeBytes: UInt64
    let uptimeSeconds: Double
}

private struct InstalledApp: Decodable, Identifiable {
    let name: String
    let bundleIdentifier: String
    let version: String
    var id: String { bundleIdentifier }
}

private struct InstalledAppsResponse: Decodable {
    let ok: Bool
    let apps: [InstalledApp]
}

private struct Alpha11ConfigStatus: Decodable {
    let ok: Bool
    let exists: Bool
    let parseable: Bool
    let schemaCompatible: Bool?
    let path: String
    let keyCount: Int
    let keys: [String]
    let modifiedAt: Double?
}

struct RootlessCoreView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var alpha11Config: Alpha11ConfigStatus?
    @State private var serviceState = "正在检测"
    @State private var connectionDetail = ""
    @State private var version = ""
    @State private var systemInfo: DeviceSystemInfo?
    @State private var installedApps: [InstalledApp] = []
    @State private var appSearch = ""
    @State private var message: String?

    private let baseURL = URL(string: "http://127.0.0.1:18080")!

    var body: some View {
        NavigationStack {
            List {
                Section("越狱核心服务") {
                    HStack {
                        Circle()
                            .fill(serviceState == "已连接" ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                        Text(serviceState)
                        Spacer()
                        if !version.isEmpty {
                            Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("重新检测服务", systemImage: "arrow.clockwise")
                    }
                    if serviceState == "未连接" && !connectionDetail.isEmpty {
                        Text("连接诊断：\(connectionDetail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let info = systemInfo {
                    Section("设备信息（只读）") {
                        LabeledContent("设备型号", value: info.productType)
                        LabeledContent("系统版本", value: info.osVersion)
                        LabeledContent("架构", value: info.architecture)
                        LabeledContent("设备名称", value: info.hostname)
                        LabeledContent("存储空间", value: "\(ByteCountFormatter.string(fromByteCount: Int64(info.diskFreeBytes), countStyle: .file)) 可用 / \(ByteCountFormatter.string(fromByteCount: Int64(info.diskTotalBytes), countStyle: .file))")
                        LabeledContent("运行时间", value: uptimeText(info.uptimeSeconds))
                    }
                }

                Section("已安装应用（只读清单）") {
                    TextField("搜索应用名称或 Bundle ID", text: $appSearch)
                    let filtered = installedApps.filter {
                        appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch) || $0.bundleIdentifier.localizedCaseInsensitiveContains(appSearch)
                    }
                    if filtered.isEmpty {
                        Text(installedApps.isEmpty ? "未读取到应用清单" : "没有匹配的应用")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { app in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                    Text(app.bundleIdentifier).font(.caption2).foregroundStyle(.secondary)
                                    if !app.version.isEmpty {
                                        Text("版本 \(app.version)").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 8)
                                let isManaged = store.managedApps.contains { $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame }
                                Button {
                                    store.addManagedApp(name: app.name, bundleIdentifier: app.bundleIdentifier)
                                    message = isManaged ? "该应用已经在管理列表中。" : "已添加应用绑定。绑定关系保存在管理器配置档案中，当前作为管理元数据使用。"
                                } label: {
                                    Label(isManaged ? "已添加" : "添加绑定", systemImage: isManaged ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isManaged || store.selectedProfile == nil)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Text("仅枚举已安装应用信息，不读取应用私有数据。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Alpha11 本地配置文件（只读诊断）") {
                    if let config = alpha11Config {
                        LabeledContent("文件状态", value: !config.exists ? "尚未创建" : (config.parseable ? "存在且可解析" : "文件格式异常"))
                        LabeledContent("结构检查", value: !config.exists ? "文件未创建" : (!config.parseable ? "无法解析" : (config.schemaCompatible == true ? "Alpha11 必需字段存在" : "缺少 Alpha11 必需字段")))
                        LabeledContent("字段数量", value: "\(config.keyCount)")
                        Text(config.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        if !config.keys.isEmpty {
                            Text("检测到字段").font(.caption).foregroundStyle(.secondary)
                            Text(config.keys.joined(separator: "、")).font(.caption2).textSelection(.enabled)
                        }
                    } else {
                        Text("尚未取得配置文件诊断结果").foregroundStyle(.secondary)
                    }
                    Button { Task { await refreshAlpha11Config() } } label: {
                        Label("重新检查 Alpha11 配置", systemImage: "arrow.clockwise")
                    }
                    Text("此处直接检查 Alpha11 正在读取的本地 plist，只显示文件状态和字段名，不读取或展示设备唯一标识的具体值。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section {
                    Text("此 Rootless 核心提供本机设备诊断、已安装应用清单和 Alpha11 plist 状态检查；配置档案由管理器本身保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rootless 核心")
            .task { await refresh() }
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
    private func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let (statusData, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("status"))
            let status = try JSONDecoder().decode(RootlessStatus.self, from: statusData)
            guard status.ok else { throw URLError(.cannotConnectToHost) }
            serviceState = "已连接"
            connectionDetail = ""
            version = status.version ?? ""

            async let systemResult = URLSession.shared.data(from: baseURL.appendingPathComponent("system"))
            async let appsResult = URLSession.shared.data(from: baseURL.appendingPathComponent("apps"))
            let (systemData, _) = try await systemResult
            let (appsData, _) = try await appsResult
            let systemResponse = try JSONDecoder().decode(DeviceSystemInfo.self, from: systemData)
            let appsResponse = try JSONDecoder().decode(InstalledAppsResponse.self, from: appsData)
            systemInfo = systemResponse
            installedApps = appsResponse.apps
            await refreshAlpha11Config()
        } catch {
            connectionDetail = error.localizedDescription
            serviceState = "未连接"
            version = ""
            systemInfo = nil
            installedApps = []
            alpha11Config = nil
        }
    }

    @MainActor
    private func refreshAlpha11Config() async {
        do {
            let url = baseURL.appendingPathComponent("config/status")
            let (data, _) = try await URLSession.shared.data(from: url)
            alpha11Config = try JSONDecoder().decode(Alpha11ConfigStatus.self, from: data)
        } catch {
            alpha11Config = nil
        }
    }

    private func uptimeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        let days = value / 86_400
        let hours = (value % 86_400) / 3_600
        let minutes = (value % 3_600) / 60
        return days > 0 ? "\(days) 天 \(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
    }

}
