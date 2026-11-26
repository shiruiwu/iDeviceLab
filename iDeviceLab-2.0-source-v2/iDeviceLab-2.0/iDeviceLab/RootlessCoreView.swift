import SwiftUI
import UniformTypeIdentifiers

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
    @State private var configImporterPresented = false
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

                Section("Alpha11 本地配置文件") {
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
                    HStack {
                        Button { Task { await refreshAlpha11Config() } } label: {
                            Label("重新检查", systemImage: "arrow.clockwise")
                        }
                        Button { configImporterPresented = true } label: {
                            Label("导入安全字段", systemImage: "square.and.arrow.down")
                        }
                        .disabled(serviceState != "已连接" || !((alpha11Config?.exists ?? false) && (alpha11Config?.schemaCompatible ?? false)))
                    }
                    Text("可导入 HWModelStr、ProductVersion、BuildVersion、HardwarePlatform、ModelNumber、RegionInfo、RegionCode、ProductType。其他字段一律忽略，原文件中的唯一标识字段保持不变。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section {
                    Text("此 Rootless 核心提供本机设备诊断、已安装应用清单，以及 Alpha11 plist 状态检查和白名单字段更新。配置档案由管理器本身保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rootless 核心")
            .task { await refresh() }
            .fileImporter(isPresented: $configImporterPresented, allowedContentTypes: [.propertyList]) { result in
                Task { await importSafeAlpha11Fields(result) }
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
    private func refresh() async {
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
    private func importSafeAlpha11Fields(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let hasScope = url.startAccessingSecurityScopedResource()
            defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [String: Any] else {
                throw NSError(domain: "iDeviceLab.ConfigImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "所选 plist 根对象必须是 Dictionary"])
            }
            let allowed: Set<String> = ["HWModelStr", "ProductVersion", "BuildVersion", "HardwarePlatform", "ModelNumber", "RegionInfo", "RegionCode", "ProductType"]
            var safeValues: [String: String] = [:]
            for key in allowed {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    safeValues[key] = value
                }
            }
            guard !safeValues.isEmpty else {
                throw NSError(domain: "iDeviceLab.ConfigImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件中没有可导入的安全字段"])
            }
            let body = try JSONSerialization.data(withJSONObject: safeValues, options: [])
            var request = URLRequest(url: baseURL.appendingPathComponent("config/update"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.httpBody = body
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let resultObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  resultObject["ok"] as? Bool == true else {
                let errorObject = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
                throw NSError(domain: "iDeviceLab.ConfigImport", code: 3, userInfo: [NSLocalizedDescriptionKey: errorObject?["error"] as? String ?? "核心拒绝了配置更新"])
            }
            let applied = resultObject["appliedKeys"] as? [String] ?? []
            let ignored = resultObject["ignoredKeys"] as? [String] ?? []
            message = "已写入 Alpha11 本地 plist。更新字段：\(applied.joined(separator: "、"))。忽略字段：\(ignored.isEmpty ? "无" : ignored.joined(separator: "、"))。请重新启动目标进程后再检查读取状态。"
            await refreshAlpha11Config()
        } catch {
            message = "配置导入失败：\(error.localizedDescription)"
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
