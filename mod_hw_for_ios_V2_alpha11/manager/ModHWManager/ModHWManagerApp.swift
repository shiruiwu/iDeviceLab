import SwiftUI
import UniformTypeIdentifiers

@main
struct ModHWManagerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    var values: [String: Any]

    init(values: [String: Any] = [:]) { self.values = values }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        values = dictionary
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return FileWrapper(regularFileWithContents: data)
    }
}

private struct Field: Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

struct ContentView: View {
    private let fields = [
        Field(key: "HWModelStr", title: "硬件模型"),
        Field(key: "ProductType", title: "产品类型"),
        Field(key: "ProductVersion", title: "系统版本"),
        Field(key: "BuildVersion", title: "系统构建号"),
        Field(key: "HardwarePlatform", title: "硬件平台"),
        Field(key: "ModelNumber", title: "销售型号"),
        Field(key: "RegionInfo", title: "区域信息"),
        Field(key: "RegionCode", title: "区域代码"),
        Field(key: "SerialNumber", title: "序列号"),
        Field(key: "UniqueDeviceID", title: "设备标识（十六进制）"),
        Field(key: "UniqueChipId", title: "芯片标识（十六进制）"),
        Field(key: "ProductId", title: "产品标识（十六进制）"),
        Field(key: "WifiAddress", title: "Wi-Fi 地址"),
        Field(key: "BluetoothAddress", title: "蓝牙地址"),
        Field(key: "EthernetMacAddress", title: "以太网地址"),
        Field(key: "MLBSerialNumber", title: "主板序列号"),
        Field(key: "InternationalMobileEquipmentIdentity", title: "IMEI"),
        Field(key: "MobileEquipmentIdentifier", title: "MEID"),
        Field(key: "IDFA", title: "广告标识"),
        Field(key: "IDFV", title: "供应商标识")
    ]

    @State private var values: [String: String] = [:]
    @State private var flags: [String: Bool] = [
        "UniqueDeviceIDData": false,
        "WifiAddressData": false,
        "BluetoothAddressData": false
    ]
    @State private var extraValues: [String: Any] = [:]
    @State private var originalKnownValues: [String: Any] = [:]
    @State private var importedDisplayValues: [String: String] = [:]
    @State private var importOpen = false
    @State private var exportOpen = false
    @State private var status = "新建配置，或导入现有 plist。"
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("配置编辑器").font(.title2.bold())
                    Text("编辑并导出插件配置。导出后需通过越狱文件管理工具放入插件读取路径。")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("导入 plist") { importOpen = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("新建空白配置") { resetConfiguration() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("检查并导出") {
                            validate()
                            if errors.isEmpty { exportOpen = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("设备与系统字段") {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.title).font(.caption).foregroundStyle(.secondary)
                            TextField(field.key, text: Binding(
                                get: { values[field.key, default: ""] },
                                set: { values[field.key] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                    }
                }

                Section("数据格式开关") {
                    Toggle("设备标识按 Data 输出", isOn: flag("UniqueDeviceIDData"))
                    Toggle("Wi-Fi 地址按 Data 输出", isOn: flag("WifiAddressData"))
                    Toggle("蓝牙地址按 Data 输出", isOn: flag("BluetoothAddressData"))
                }

                if !errors.isEmpty {
                    Section("格式错误") {
                        ForEach(errors, id: \.self) { error in
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }

                Section("状态") {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("mod_hw 管理器")
            .fileImporter(isPresented: $importOpen, allowedContentTypes: [.propertyList]) { result in
                importConfiguration(result)
            }
            .fileExporter(
                isPresented: $exportOpen,
                document: ConfigDocument(values: output()),
                contentType: .propertyList,
                defaultFilename: "com.modhw.ios.devices.plist"
            ) { result in
                switch result {
                case .success(let url): status = "已导出：\(url.lastPathComponent)"
                case .failure(let error): status = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { flags[key, default: false] }, set: { flags[key] = $0 })
    }

    private func importConfiguration(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let knownKeys = Set(fields.map(\.key) + Array(flags.keys))
            extraValues = dictionary.filter { !knownKeys.contains($0.key) }
            originalKnownValues = dictionary.filter { knownKeys.contains($0.key) }
            importedDisplayValues = [:]
            for field in fields {
                let display = Self.displayValue(dictionary[field.key])
                values[field.key] = display
                if dictionary[field.key] != nil { importedDisplayValues[field.key] = display }
            }
            for key in Array(flags.keys) { flags[key] = dictionary[key] as? Bool ?? false }
            errors = []
            status = "已导入：\(url.lastPathComponent)；未知字段已保留。"
        } catch {
            status = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetConfiguration() {
        values = [:]
        for field in fields { values[field.key] = "" }
        flags = ["UniqueDeviceIDData": false, "WifiAddressData": false, "BluetoothAddressData": false]
        extraValues = [:]
        originalKnownValues = [:]
        importedDisplayValues = [:]
        errors = []
        status = "已新建空白配置。"
    }

    private func output() -> [String: Any] {
        var dictionary = extraValues
        for field in fields {
            let current = values[field.key, default: ""]
            if let imported = importedDisplayValues[field.key], imported == current,
               let original = originalKnownValues[field.key] {
                dictionary[field.key] = original
            } else {
                dictionary[field.key] = current
            }
        }
        for (key, value) in flags { dictionary[key] = value }
        return dictionary
    }

    private static func displayValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let data = value as? Data {
            return data.map { String(format: "%02X", $0) }.joined()
        }
        return "<\(type(of: value))：保留原值，编辑后将转为文本>"
    }

    private static func isASCIIHex(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) ||
            (65...70).contains(scalar.value) ||
            (97...102).contains(scalar.value)
        }
    }

    private func validate() {
        var found: [String] = []
        let uid = values["UniqueDeviceID", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        if uid.isEmpty {
            found.append("UniqueDeviceID 不能为空：原插件在该字段缺失时会提前停止加载配置。")
        } else if uid.count % 2 != 0 || !Self.isASCIIHex(uid) {
            found.append("UniqueDeviceID 必须是偶数长度的十六进制字符串。")
        }

        for key in ["ProductId", "UniqueChipId"] {
            let value = values[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && (value.count % 2 != 0 || !Self.isASCIIHex(value)) {
                found.append("\(key) 必须是偶数长度的十六进制字符串。")
            }
        }

        for key in ["WifiAddress", "BluetoothAddress", "EthernetMacAddress"] {
            let value = values[key, default: ""].replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            if !value.isEmpty && (value.count != 12 || !Self.isASCIIHex(value)) {
                found.append("\(key) 应为 6 组十六进制地址（可带冒号或短横线）。")
            }
        }

        errors = found
        status = found.isEmpty ? "基础格式检查通过，请核对配置内容。" : "发现格式问题，请修正后重新导出。"
    }
}