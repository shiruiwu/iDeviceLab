import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProfileManagerView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var showingImporter = false
    @State private var exportURL: URL?
    @State private var alertMessage: String?
    @State private var newAppName = ""
    @State private var newAppBundleID = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                if let profile = store.selectedProfile {
                    Form {
                        Section {
                            TextField("应用名称", text: $newAppName)
                            TextField("Bundle ID（应用标识符）", text: $newAppBundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                store.addManagedApp(name: newAppName, bundleIdentifier: newAppBundleID)
                                newAppName = ""
                                newAppBundleID = ""
                            } label: {
                                Label("添加并绑定当前配置", systemImage: "app.badge.plus")
                            }
                            .disabled(newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if store.managedApps.isEmpty {
                                Text("尚未添加应用。填写应用名称和 Bundle ID 后，可将它关联到当前配置。")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            ForEach(store.managedApps) { app in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                            Text(app.bundleIdentifier).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteManagedApp(app)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    Picker("关联配置", selection: Binding(
                                        get: { store.managedApps.first(where: { $0.id == app.id })?.profileID ?? store.profiles.first?.id ?? UUID() },
                                        set: { newID in
                                            var changed = app
                                            changed.profileID = newID
                                            store.updateManagedApp(changed)
                                        }
                                    )) {
                                        ForEach(store.profiles) { item in
                                            Text(item.name).tag(item.id)
                                        }
                                    }
                                    HStack {
                                        Button {
                                            openManagedApp(app)
                                        } label: {
                                            Label("打开应用", systemImage: "arrow.up.forward.app")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        Spacer()
                                        if let boundProfile = store.profiles.first(where: { $0.id == app.profileID }) {
                                            Text("已绑定：\(boundProfile.name)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    if let boundProfile = store.profiles.first(where: { $0.id == app.profileID }) {
                                        DisclosureGroup("查看绑定的模拟配置") {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("设备型号：\(boundProfile.deviceModel)")
                                                Text("测试系统：iOS \(boundProfile.iosVersion)")
                                                Text("语言 / 地区：\(boundProfile.language) / \(boundProfile.region)")
                                                Text("时区：\(boundProfile.timeZone)")
                                                Text("网络场景：\(boundProfile.network)")
                                                Text("测试坐标：\(String(format: "%.4f", boundProfile.latitude)), \(String(format: "%.4f", boundProfile.longitude))")
                                                Text("测试 UUID：\(boundProfile.testIdentifier)")
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("应用选择与配置绑定")
                        } footer: {
                            Text("当前版本采用手动登记应用名称和 Bundle ID。iOS 不向普通应用开放完整已安装应用清单；登记和绑定只保存管理信息，不会自动把配置注入第三方 App，也不会自动克隆应用。")
                        }

                        Section("配置管理") {
                            Picker("当前配置", selection: Binding(
                                get: { store.selectedID ?? profile.id },
                                set: { store.selectedID = $0 }
                            )) {
                                ForEach(store.profiles) { item in
                                    Text(item.name).tag(item.id)
                                }
                            }
                            TextField("配置名称", text: binding(\.name, profile: profile))
                            Button { store.addProfile() } label: {
                                Label("新增独立配置", systemImage: "plus.circle")
                            }
                            Button { store.duplicateSelected() } label: {
                                Label("复制当前配置", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) { store.deleteSelected() } label: {
                                Label("删除当前配置", systemImage: "trash")
                            }
                        }

                        Section {
                            HStack { Picker("设备型号", selection: binding(\.deviceModel, profile: profile)) { ForEach(DeviceProfile.deviceModels, id: \.self) { Text($0).tag($0) } }; randomButton("deviceModel") }
                            HStack { Picker("测试系统版本", selection: binding(\.iosVersion, profile: profile)) { ForEach(DeviceProfile.iosVersions, id: \.self) { Text($0).tag($0) } }; randomButton("iosVersion") }
                            HStack { Picker("语言", selection: binding(\.language, profile: profile)) { ForEach(DeviceProfile.languages, id: \.self) { Text($0).tag($0) } }; randomButton("language") }
                            HStack { Picker("地区", selection: binding(\.region, profile: profile)) { ForEach(DeviceProfile.regions, id: \.self) { Text($0).tag($0) } }; randomButton("region") }
                            HStack { Picker("时区", selection: binding(\.timeZone, profile: profile)) { ForEach(DeviceProfile.timeZones, id: \.self) { Text($0).tag($0) } }; randomButton("timeZone") }
                            HStack { Picker("网络测试类型", selection: binding(\.network, profile: profile)) { ForEach(DeviceProfile.networkTypes, id: \.self) { Text($0).tag($0) } }; randomButton("network") }
                        } header: {
                            Text("环境参数")
                        } footer: {
                            Text("这些选项只记录测试场景，不会改变 iOS 的真实设备型号、系统版本、网络或定位。")
                        }

                        Section("测试数值") {
                            HStack { Stepper("电量测试值：\(profile.batteryPercent)%", value: binding(\.batteryPercent, profile: profile), in: 1...100); randomButton("batteryPercent") }
                            HStack { Stepper("内存测试标签：\(profile.memoryGB) GB", value: binding(\.memoryGB, profile: profile), in: 2...16, step: 2); randomButton("memoryGB") }
                            HStack { Text("测试 UUID"); Spacer(); randomButton("testIdentifier") }
                            TextField("测试 UUID", text: binding(\.testIdentifier, profile: profile))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            HStack {
                                Text("纬度")
                                Spacer()
                                TextField("纬度", value: binding(\.latitude, profile: profile), format: .number.precision(.fractionLength(4)))
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text("经度")
                                Spacer()
                                TextField("经度", value: binding(\.longitude, profile: profile), format: .number.precision(.fractionLength(4)))
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                            }
                            Button("随机测试坐标") { store.randomize("location") }
                        }

                        Section("随机生成") {
                            Button { store.randomizeAll() } label: {
                                Label("全部参数一键随机", systemImage: "shuffle")
                            }
                            Text("也可以使用各参数对应的随机按钮单独生成。")
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Section("配置备份") {
                            Button { prepareExport() } label: {
                                Label("生成配置备份 JSON", systemImage: "square.and.arrow.up")
                            }
                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    Label("分享 / 保存 JSON 文件", systemImage: "square.and.arrow.up.on.square")
                                }
                            }
                            Button { showingImporter = true } label: {
                                Label("导入配置 JSON", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) { Image(systemName: "square.stack.3d.up").font(.largeTitle); Text("没有配置") }
                }
                footer
            }
            .navigationBarHidden(true)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try store.importData(data)
                    exportURL = nil
                    alertMessage = "配置导入成功"
                } catch {
                    alertMessage = "导入失败：\(error.localizedDescription)"
                }
            }
            .alert("iDevice Lab", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .accentColor(.cyan)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("iDevice Lab").font(.largeTitle.bold())
                Text("DEVICE PROFILE MANAGER").font(.caption2).tracking(2).foregroundColor(.cyan)
            }
            Spacer()
            Button { store.addProfile() } label: {
                Image(systemName: "plus").font(.headline).padding(11)
                    .background(Color.cyan.opacity(0.18)).clipShape(Circle())
            }
            .accessibilityLabel("新增配置")
        }
        .padding()
        .background(Color.black)
    }

    private var footer: some View {
        Text("自动保存已启用 · 配置值不等于真实硬件身份")
            .font(.caption2).foregroundColor(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DeviceProfile, T>, profile: DeviceProfile) -> Binding<T> {
        Binding(
            get: { store.profiles.first(where: { $0.id == profile.id })?[keyPath: keyPath] ?? profile[keyPath: keyPath] },
            set: { newValue in
                guard var latest = store.profiles.first(where: { $0.id == profile.id }) else { return }
                latest[keyPath: keyPath] = newValue
                store.update(latest)
            }
        )
    }

    private func randomButton(_ field: String) -> some View {
        Button("随机") { store.randomize(field) }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func openManagedApp(_ app: ManagedApp) {
        let scheme: String
        switch app.bundleIdentifier.lowercased() {
        case "com.jiangjia.gif":
            scheme = "kwai://"
        case "com.kuaishou.nebula":
            scheme = "ksnebula://"
        default:
            alertMessage = "暂未配置此应用的启动地址。当前已支持快手主版和快手极速版。"
            return
        }
        guard let url = URL(string: scheme) else {
            alertMessage = "应用启动地址无效"
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                self.alertMessage = success ? "已向 iOS 发出打开\(app.name) 的请求。" : "无法打开\(app.name)。请确认手机已安装对应应用。"
            }
        }
    }

    private func prepareExport() {
        guard let data = store.exportData() else {
            alertMessage = "没有可导出的配置"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iDeviceLab-Profiles-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            alertMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}
