import Foundation

struct DeviceProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "新测试环境"
    var deviceModel: String = "iPhone 12"
    var iosVersion: String = "16.2"
    var language: String = "zh-Hans"
    var region: String = "CN"
    var timeZone: String = "Asia/Shanghai"
    var latitude: Double = 31.2304
    var longitude: Double = 121.4737
    var network: String = "Wi-Fi"
    var batteryPercent: Int = 85
    var memoryGB: Int = 4
    var testIdentifier: String = UUID().uuidString
    var serialNumber: String? = nil
    var imei: String? = nil
    var meid: String? = nil
    var wifiAddress: String? = nil
    var bluetoothAddress: String? = nil
    var uniqueDeviceID: String? = nil
    var productId: String? = nil
    var uniqueChipId: String? = nil
    var productType: String? = "iPhone13,2"
    var hwModelStr: String? = "D53gAP"
    var idfa: String? = nil
    var idfv: String? = nil
    var uniqueDeviceIDData: Bool? = nil
    var wifiAddressData: Bool? = nil
    var bluetoothAddressData: Bool? = nil
    var updatedAt: Date = Date()

    var hookConfiguration: [String: Any] {
        var values: [String: Any] = [:]
        let fields: [(String, String?)] = [
            ("SerialNumber", serialNumber),
            ("InternationalMobileEquipmentIdentity", imei),
            ("MobileEquipmentIdentifier", meid),
            ("WifiAddress", wifiAddress),
            ("BluetoothAddress", bluetoothAddress),
            ("UniqueDeviceID", uniqueDeviceID),
            ("ProductId", productId),
            ("UniqueChipId", uniqueChipId),
            ("ProductType", productType),
            ("HWModelStr", hwModelStr),
            ("IDFA", idfa),
            ("IDFV", idfv)
        ]
        for (key, value) in fields {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let uniqueDeviceIDData { values["UniqueDeviceIDData"] = uniqueDeviceIDData }
        if let wifiAddressData { values["WifiAddressData"] = wifiAddressData }
        if let bluetoothAddressData { values["BluetoothAddressData"] = bluetoothAddressData }
        return values
    }

    var isHookConfigurationReady: Bool {
        guard let value = uniqueDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count == 40,
              value.range(of: "^[0-9A-Fa-f]{40}$", options: .regularExpression) != nil else { return false }
        return true
    }

    static let deviceModels = ["iPhone 12", "iPhone 12 Pro", "iPhone 13", "iPhone 13 Pro", "iPhone 14", "iPhone 14 Pro", "iPhone 15", "iPhone 15 Pro"]
    static let iosVersions = ["16.2", "16.6", "17.0", "17.4", "17.5", "18.0"]
    static let languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
    static let regions = ["CN", "US", "JP", "KR", "GB", "HK", "TW"]
    static let timeZones = ["Asia/Shanghai", "Asia/Tokyo", "America/New_York", "Europe/London", "Asia/Seoul"]
    static let networkTypes = ["Wi-Fi", "蜂窝网络", "离线测试", "弱网测试"]

    static func languageDisplay(_ code: String) -> String {
        let name: String
        switch code {
        case "zh-Hans": name = "简体中文"
        case "zh-Hant": name = "繁体中文"
        case "en": name = "英语"
        case "ja": name = "日语"
        case "ko": name = "韩语"
        default: return code
        }
        return "\(name)（\(code)）"
    }

    static func regionDisplay(_ code: String) -> String {
        let name: String
        switch code {
        case "CN": name = "中国大陆"
        case "US": name = "美国"
        case "JP": name = "日本"
        case "KR": name = "韩国"
        case "GB": name = "英国"
        case "HK": name = "中国香港"
        case "TW": name = "中国台湾"
        default: return code
        }
        return "\(name)（\(code)）"
    }

    static func timeZoneDisplay(_ identifier: String) -> String {
        let name: String
        switch identifier {
        case "Asia/Shanghai": name = "中国标准时间 · 上海"
        case "Asia/Tokyo": name = "日本标准时间 · 东京"
        case "America/New_York": name = "美国东部时间 · 纽约"
        case "Europe/London": name = "英国时间 · 伦敦"
        case "Asia/Seoul": name = "韩国标准时间 · 首尔"
        default: return identifier
        }
        return "\(name)（\(identifier)）"
    }
}

struct ProfileArchive: Codable {
    var formatVersion: Int = 2
    var exportedAt: Date = Date()
    var profiles: [DeviceProfile]
    var managedApps: [ManagedApp]?
}


struct ManagedApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleIdentifier: String
    var profileID: UUID
}


struct ProfileAppOption: Identifiable, Equatable {
    let name: String
    let bundleIdentifier: String
    var id: String { bundleIdentifier }
}
