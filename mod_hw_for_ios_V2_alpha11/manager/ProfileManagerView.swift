import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProfileManagerView: View {
    var availableApps: [ProfileAppOption] = []
    var onOperation: ((String, Bool, String) -> Void)? = nil
    @EnvironmentObject private var store: ProfileStore
    @State private var showingImporter = false
    @State private var exportURL: URL?
    @State private var alertMessage: String?
    @State private var newAppName = ""
    @State private var newAppBundleID = ""
    @State private var pendingApplyProfile: DeviceProfile?
    @State private var pendingApplyBundleID: String?
    @State private var showApplyConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                if let profile = store.selectedProfile {
                    profileForm(profile: profile)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up").font(.largeTitle)
                        Text("没有配置")
                    }
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
            .confirmationDialog("应用原作者 Hook 配置", isPresented: $showApplyConfirmation, titleVisibility: .visible) {
                Button("确认写入并备份旧配置", role: .destructive) { applyPendingProfile() }
                Button("取消", role: .cancel) {
                    pendingApplyProfile = nil
                    pendingApplyBundleID = nil
                }
            } message: {
                Text(pendingApplyBundleID == "__global__" ? "将把当前配置写入全局 Hook 配置文件。旧文件会先备份；重新启动需要应用全局配置的目标应用后生效。" : "将把当前配置写入所选应用的分应用 Hook 配置文件。旧文件会先备份；强制关闭并重新打开目标应用后生效。")
            }
        }
        .accentColor(.cyan)
    }

    private func profileForm(profile: DeviceProfile) -> some View {
        Form {
            appBindingSection(profile: profile)
            profileManagementSection(profile: profile)
            environmentSection(profile: profile)
            testValuesSection(profile: profile)
            hookConfigurationSection(profile: profile)
            randomizationSection
            backupSection
        }
    }

    private func appBindingSection(profile: DeviceProfile) -> some View {
        Section {
            if !availableApps.isEmpty {
                Picker("从 Core 应用清单选择", selection: $newAppBundleID) {
                    Text("手动填写").tag("")
                    ForEach(availableApps) { app in
                        Text(app.name).tag(app.bundleIdentifier)
                    }
                }
                .onChange(of: newAppBundleID) { value in
                    if let selected = availableApps.first(where: { $0.bundleIdentifier == value }) {
                        newAppName = selected.name
                    }
                }
            }
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
                Text("尚未添加应用。可从 Core 清单选择，也可手动填写 Bundle ID。")
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach(store.managedApps) { app in
                managedAppRow(app)
            }
        } header: {
            Text("应用选择与配置绑定")
        } footer: {
            Text("配置按 Bundle ID 保存为分应用 Hook 配置。写入后需强制关闭并重新打开目标应用，Hook 才会重新读取。")
        }
    }

    private func managedAppRow(_ app: ManagedApp) -> some View {
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
                    Button {
                        pendingApplyProfile = boundProfile
                        pendingApplyBundleID = app.bundleIdentifier
                        showApplyConfirmation = true
                    } label: {
                        Label("应用 Hook", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!boundProfile.isHookConfigurationReady)
                    Text("已绑定：\(boundProfile.name)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            if let boundProfile = store.profiles.first(where: { $0.id == app.profileID }) {
                DisclosureGroup("查看绑定的配置") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("设备型号：\(boundProfile.deviceModel)")
                        Text("测试系统：iOS \(boundProfile.iosVersion)")
                        Text("语言 / 地区：\(boundProfile.language) / \(boundProfile.region)")
                        Text("时区：\(boundProfile.timeZone)")
                        Text("网络场景：\(boundProfile.network)")
                        Text("测试坐标：\(String(format: "%.4f", boundProfile.latitude)), \(String(format: "%.4f", boundProfile.longitude))")
                        Text("测试 UUID：\(boundProfile.testIdentifier)")
                        Text("Hook UDID：\(boundProfile.uniqueDeviceID ?? "未填写")")
                    }
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

        private func profileManagementSection(profile: DeviceProfile) -> some View {
        Section {
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
        } header: {
            Text("配置管理")
        }
    }

    private func environmentSection(profile: DeviceProfile) -> some View {
        Section {
            HStack {
                Picker("设备型号", selection: binding(\.deviceModel, profile: profile)) {
                    ForEach(DeviceProfile.deviceModels, id: \.self) { Text($0).tag($0) }
                }
                randomButton("deviceModel")
            }
            HStack {
                Picker("测试系统版本", selection: binding(\.iosVersion, profile: profile)) {
                    ForEach(DeviceProfile.iosVersions, id: \.self) { Text($0).tag($0) }
                }
                randomButton("iosVersion")
            }
            HStack {
                Picker("语言", selection: binding(\.language, profile: profile)) {
                    ForEach(DeviceProfile.languages, id: \.self) { Text(DeviceProfile.languageDisplay($0)).tag($0) }
                }
                randomButton("language")
            }
            HStack {
                Picker("地区", selection: binding(\.region, profile: profile)) {
                    ForEach(DeviceProfile.regions, id: \.self) { Text(DeviceProfile.regionDisplay($0)).tag($0) }
                }
                randomButton("region")
            }
            HStack {
                Picker("时区", selection: binding(\.timeZone, profile: profile)) {
                    ForEach(DeviceProfile.timeZones, id: \.self) { Text(DeviceProfile.timeZoneDisplay($0)).tag($0) }
                }
                randomButton("timeZone")
            }
            HStack {
                Picker("网络测试类型", selection: binding(\.network, profile: profile)) {
                    ForEach(DeviceProfile.networkTypes, id: \.self) { Text($0).tag($0) }
                }
                randomButton("network")
            }
        } header: {
            Text("环境参数")
        } footer: {
            Text("这些选项只记录测试场景，不会改变 iOS 的真实设备型号、系统版本、网络或定位。")
        }
    }

    private func testValuesSection(profile: DeviceProfile) -> some View {
        Section {
            HStack {
                Stepper("电量测试值：\(profile.batteryPercent)%", value: binding(\.batteryPercent, profile: profile), in: 1...100)
                randomButton("batteryPercent")
            }
            HStack {
                Stepper("内存测试标签：\(profile.memoryGB) GB", value: binding(\.memoryGB, profile: profile), in: 2...16, step: 2)
                randomButton("memoryGB")
            }
            HStack {
                Text("测试 UUID")
                Spacer()
                randomButton("testIdentifier")
            }
            TextField("测试 UUID", text: binding(\.testIdentifier, profile: profile))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            HStack {
                Text("纬度")
                Spacer()
                TextField("纬度", value: binding(\.latitude, profile: profile), format: .number.precision(.fractionLength(4)))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            HStack {
                Text("经度")
                Spacer()
                TextField("经度", value: binding(\.longitude, profile: profile), format: .number.precision(.fractionLength(4)))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            Button("随机测试坐标") { store.randomize("location") }
        } header: {
            Text("测试数值")
        }
    }

    private func hookConfigurationSection(profile: DeviceProfile) -> some View {
        Section {
            TextField("序列号", text: optionalBinding(\.serialNumber, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("IMEI（15 位）", text: optionalBinding(\.imei, profile: profile))
                .keyboardType(.numberPad)
            TextField("MEID（14 位十六进制）", text: optionalBinding(\.meid, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("Wi-Fi 地址（MAC）", text: optionalBinding(\.wifiAddress, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("蓝牙地址（MAC）", text: optionalBinding(\.bluetoothAddress, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("设备唯一标识（40 位十六进制）", text: optionalBinding(\.uniqueDeviceID, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("产品标识（12 位十六进制）", text: optionalBinding(\.productId, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("芯片唯一标识（12 位十六进制）", text: optionalBinding(\.uniqueChipId, profile: profile))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("产品型号代码（例如 iPhone13,2）", text: optionalBinding(\.productType, profile: profile))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("硬件型号代码（例如 D53gAP）", text: optionalBinding(\.hwModelStr, profile: profile))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("广告标识符 IDFA（UUID）", text: optionalBinding(\.idfa, profile: profile))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("供应商标识符 IDFV（UUID）", text: optionalBinding(\.idfv, profile: profile))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("UDID 返回 NSData", isOn: boolBinding(\.uniqueDeviceIDData, profile: profile))
            Toggle("Wi-Fi MAC 返回 NSData", isOn: boolBinding(\.wifiAddressData, profile: profile))
            Toggle("蓝牙 MAC 地址返回 NSData", isOn: boolBinding(\.bluetoothAddressData, profile: profile))
            Button {
                store.randomizeHookIdentifiers()
            } label: {
                Label("生成一组 Hook 测试标识", systemImage: "shuffle")
            }

            Button {
                pendingApplyProfile = profile
                pendingApplyBundleID = "__global__"
                showApplyConfirmation = true
            } label: {
                Label("应用为全局 Hook 配置", systemImage: "globe")
            }
            .disabled(!profile.isHookConfigurationReady)
            Text(profile.isHookConfigurationReady
                 ? "UDID 基本格式已满足；应用前仍会由 Root Helper 校验全部字段。"
                 : "填写或生成 40 位十六进制 UDID 后，才可应用到指定应用。")
                .font(.caption).foregroundColor(.secondary)
        } header: {
            Text("原作者 Hook 硬件参数")
        } footer: {
            Text("可应用为全局配置（写入 com.modhw.ios.devices.plist），也可按 Bundle ID 单独应用。分应用配置优先于全局配置。仅影响已注入 Hook 且重新启动的目标应用，不改变基带或真实硬件。")
        }
    }

    private var randomizationSection: some View {
        Section {
            Button { store.randomizeAll() } label: {
                Label("全部参数一键随机", systemImage: "shuffle")
            }
            Text("也可以使用各参数对应的随机按钮单独生成。")
                .font(.caption).foregroundColor(.secondary)
        } header: {
            Text("随机生成")
        }
    }

    private var backupSection: some View {
        Section {
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
        } header: {
            Text("配置备份")
        }
    }

private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("iDevice Lab").font(.largeTitle.bold()).foregroundColor(.white)
                Text("设备配置管理").font(.caption2).tracking(2).foregroundColor(.white.opacity(0.82))
            }
            Spacer()
            Button { store.addProfile() } label: {
                Image(systemName: "plus").font(.headline).padding(11)
                    .background(Color.white.opacity(0.20)).clipShape(Circle()).foregroundColor(.white)
            }
            .accessibilityLabel("新增配置")
        }
        .padding()
        .background(LinearGradient(colors: [Color(red: 0.08, green: 0.42, blue: 0.92), Color(red: 0.20, green: 0.70, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var footer: some View {
        Text("自动保存已启用 · Hook 参数仅对目标应用生效")
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

    private func optionalBinding(_ keyPath: WritableKeyPath<DeviceProfile, String?>, profile: DeviceProfile) -> Binding<String> {
        Binding(
            get: { store.profiles.first(where: { $0.id == profile.id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var latest = store.profiles.first(where: { $0.id == profile.id }) else { return }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                latest[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                store.update(latest)
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DeviceProfile, Bool?>, profile: DeviceProfile) -> Binding<Bool> {
        Binding(
            get: { store.profiles.first(where: { $0.id == profile.id })?[keyPath: keyPath] ?? false },
            set: { value in
                guard var latest = store.profiles.first(where: { $0.id == profile.id }) else { return }
                latest[keyPath: keyPath] = value
                store.update(latest)
            }
        )
    }

    private func randomButton(_ field: String) -> some View {
        Button("随机") { store.randomize(field) }
            .font(.caption).buttonStyle(.bordered).controlSize(.small)
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

    private func applyPendingProfile() {
        guard let profile = pendingApplyProfile, let bundleID = pendingApplyBundleID else { return }
        guard profile.isHookConfigurationReady else {
            alertMessage = "UniqueDeviceID 必须是 40 位十六进制字符串。"
            onOperation?("Hook 配置应用", false, alertMessage ?? "")
            return
        }
        Task {
            do {
                let helperStatus = try await MaintenanceClient.request(action: "status")
                guard helperStatus.paired == true else {
                    alertMessage = "Root Helper 尚未与当前管理器配对。请先到「设置 → 高级维护与 iPhone 12 最终验收」复制配对命令并在越狱终端执行。"
                    onOperation?("Hook 配置应用", false, alertMessage ?? "")
                    return
                }
                let isGlobal = bundleID == "__global__"
                let result = try await MaintenanceClient.request(
                    action: isGlobal ? "apply-global-profile" : "apply-profile",
                    bundleID: isGlobal ? nil : bundleID,
                    profile: profile.hookConfiguration,
                    confirm: true
                )
                alertMessage = result.ok
                    ? (result.output ?? "Hook 配置文件已写入。请执行一次 Respring，再强制关闭并重新打开目标 App；写入成功不等于运行时 Hook 已验证。")
                    : (result.error ?? result.output ?? "Hook 配置写入失败。")
                onOperation?(isGlobal ? "全局 Hook 配置应用" : "分 App Hook 配置应用",
                             result.ok, result.output ?? result.error ?? "")
            } catch {
                alertMessage = "Hook 配置写入失败：\(error.localizedDescription)"
                onOperation?("Hook 配置应用", false, error.localizedDescription)
            }
            pendingApplyProfile = nil
            pendingApplyBundleID = nil
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
