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
    var updatedAt: Date = Date()

    static let deviceModels = ["iPhone 12", "iPhone 12 Pro", "iPhone 13", "iPhone 13 Pro", "iPhone 14", "iPhone 14 Pro", "iPhone 15", "iPhone 15 Pro"]
    static let iosVersions = ["16.2", "16.6", "17.0", "17.4", "17.5", "18.0"]
    static let languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
    static let regions = ["CN", "US", "JP", "KR", "GB", "HK", "TW"]
    static let timeZones = ["Asia/Shanghai", "Asia/Tokyo", "America/New_York", "Europe/London", "Asia/Seoul"]
    static let networkTypes = ["Wi-Fi", "蜂窝网络", "离线测试", "弱网测试"]
}

struct ProfileArchive: Codable {
    var formatVersion: Int = 1
    var exportedAt: Date = Date()
    var profiles: [DeviceProfile]
}
