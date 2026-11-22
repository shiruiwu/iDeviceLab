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

struct RootlessCoreView: View {
    @State private var serviceState = "正在检测"
    @State private var version = ""
    @State private var profiles: [RootlessProfile] = []
    @State private var selected = ""
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
            version = status.version ?? ""

            let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("profiles"))
            let response = try JSONDecoder().decode(RootlessProfilesResponse.self, from: data)
            profiles = response.profiles
            selected = response.selected
        } catch {
            serviceState = "未连接"
            version = ""
            profiles = []
            selected = ""
        }
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
