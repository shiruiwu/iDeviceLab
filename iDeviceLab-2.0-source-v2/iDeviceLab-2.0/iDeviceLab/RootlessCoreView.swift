import SwiftUI

private struct RootlessStatus: Decodable {
    let ok: Bool
    let service: String?
    let version: String?
}

private struct RootlessProfile: Decodable, Identifiable {
    let id: String
    let name: String
    let createdAt: Double?
}

private struct RootlessProfilesResponse: Decodable {
    let ok: Bool
    let profiles: [RootlessProfile]
    let selected: String
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

struct RootlessCoreView: View {
    @State private var serviceState = "正在检测"
    @State private var connectionDetail = ""
    @State private var version = ""
    @State private var profiles: [RootlessProfile] = []
    @State private var selected = ""
    @State private var systemInfo: DeviceSystemInfo?
    @State private var installedApps: [InstalledApp] = []
    @State private var appSearch = ""
    @State private var newName = ""
    @State private var message: String?
    @State private var isBusy = false

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
                        Text("连接诊断：\\(connectionDetail)")
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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                Text(app.bundleIdentifier).font(.caption2).foregroundStyle(.secondary)
                                if !app.version.isEmpty {
                                    Text("版本 \(app.version)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Text("仅枚举已安装应用信息，不读取应用私有数据。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("本地配置记录") {
                    HStack {
                        TextField("新配置名称", text: $newName)
                        Button("新增") {
                            Task { await createProfile() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy || serviceState != "已连接")
                    }

                    if profiles.isEmpty {
                        Text("核心服务中还没有配置记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                    Text(profile.id).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected == profile.id {
                                    Label("当前", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Button("切换") {
                                        Task { await selectProfile(profile) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("此 Rootless 核心目前提供本机配置记录与自动化接口。它不会伪造硬件标识，也不会修改其他应用的安全检测结果。")
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

            async let profileResult = URLSession.shared.data(from: baseURL.appendingPathComponent("profiles"))
            async let systemResult = URLSession.shared.data(from: baseURL.appendingPathComponent("system"))
            async let appsResult = URLSession.shared.data(from: baseURL.appendingPathComponent("apps"))
            let (profileData, _) = try await profileResult
            let (systemData, _) = try await systemResult
            let (appsData, _) = try await appsResult
            let response = try JSONDecoder().decode(RootlessProfilesResponse.self, from: profileData)
            let systemResponse = try JSONDecoder().decode(DeviceSystemInfo.self, from: systemData)
            let appsResponse = try JSONDecoder().decode(InstalledAppsResponse.self, from: appsData)
            profiles = response.profiles
            selected = response.selected
            systemInfo = systemResponse
            installedApps = appsResponse.apps
        } catch {
            connectionDetail = error.localizedDescription
            serviceState = "未连接"
            version = ""
            profiles = []
            selected = ""
            systemInfo = nil
            installedApps = []
        }
    }

    private func uptimeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        let days = value / 86_400
        let hours = (value % 86_400) / 3_600
        let minutes = (value % 3_600) / 60
        return days > 0 ? "\(days) 天 \(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
    }

    @MainActor
    private func createProfile() async {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("profiles/new"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "name", value: newName)]
        guard let url = components.url else { return }
        await sendAction(url: url, success: "配置已创建")
        newName = ""
    }

    @MainActor
    private func selectProfile(_ profile: RootlessProfile) async {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("profiles/select"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "id", value: profile.id)]
        guard let url = components.url else { return }
        await sendAction(url: url, success: "已切换到：\(profile.name)")
    }

    @MainActor
    private func sendAction(url: URL, success: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard result?["ok"] as? Bool == true else {
                throw NSError(domain: "iDeviceLab", code: 1, userInfo: [NSLocalizedDescriptionKey: result?["error"] as? String ?? "操作失败"])
            }
            message = success
            await refresh()
        } catch {
            message = "操作失败：\(error.localizedDescription)"
        }
    }
}
