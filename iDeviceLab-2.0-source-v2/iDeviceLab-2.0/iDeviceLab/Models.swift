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


struct ManagedApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleIdentifier: String
    var profileID: UUID
}


struct AppMaintenanceItem: Identifiable, Codable, Equatable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let version: String
    let containerAvailable: Bool
    let cachesBytes: Int64
    let temporaryBytes: Int64
    let cachesFileCount: Int
    let temporaryFileCount: Int
    let cachesScanStatus: String
    let temporaryScanStatus: String
    let cachesScanError: String
    let temporaryScanError: String
    let cleanableBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case name, bundleIdentifier, version, containerAvailable, cachesBytes, temporaryBytes
        case cachesFileCount, temporaryFileCount, cachesScanStatus, temporaryScanStatus
        case cachesScanError, temporaryScanError, cleanableBytes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? bundleIdentifier
        version = try values.decodeIfPresent(String.self, forKey: .version) ?? ""
        containerAvailable = try values.decodeIfPresent(Bool.self, forKey: .containerAvailable) ?? false
        cachesBytes = try values.decodeIfPresent(Int64.self, forKey: .cachesBytes) ?? 0
        temporaryBytes = try values.decodeIfPresent(Int64.self, forKey: .temporaryBytes) ?? 0
        cachesFileCount = try values.decodeIfPresent(Int.self, forKey: .cachesFileCount) ?? 0
        temporaryFileCount = try values.decodeIfPresent(Int.self, forKey: .temporaryFileCount) ?? 0
        cachesScanStatus = try values.decodeIfPresent(String.self, forKey: .cachesScanStatus) ?? "unknown"
        temporaryScanStatus = try values.decodeIfPresent(String.self, forKey: .temporaryScanStatus) ?? "unknown"
        cachesScanError = try values.decodeIfPresent(String.self, forKey: .cachesScanError) ?? ""
        temporaryScanError = try values.decodeIfPresent(String.self, forKey: .temporaryScanError) ?? ""
        cleanableBytes = try values.decodeIfPresent(Int64.self, forKey: .cleanableBytes) ?? (cachesBytes + temporaryBytes)
    }
}

struct OrphanedContainerItem: Identifiable, Codable, Equatable {
    var id: String { containerUUID }
    let bundleIdentifier: String
    let containerUUID: String
    let accessible: Bool
    let containerBytes: Int64
    let containerScanStatus: String
    let containerScanError: String
    let diagnosticReason: String

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, containerUUID, accessible, containerBytes
        case containerScanStatus, containerScanError, diagnosticReason
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        containerUUID = try values.decode(String.self, forKey: .containerUUID)
        accessible = try values.decodeIfPresent(Bool.self, forKey: .accessible) ?? false
        containerBytes = try values.decodeIfPresent(Int64.self, forKey: .containerBytes) ?? 0
        containerScanStatus = try values.decodeIfPresent(String.self, forKey: .containerScanStatus) ?? "unknown"
        containerScanError = try values.decodeIfPresent(String.self, forKey: .containerScanError) ?? ""
        diagnosticReason = try values.decodeIfPresent(String.self, forKey: .diagnosticReason)
            ?? "该结果来自旧版 Core，未提供残留判定依据。"
    }
}

struct AppMaintenanceResponse: Codable {
    let ok: Bool
    let apps: [AppMaintenanceItem]
    let orphanedContainerCount: Int
    let orphanedContainers: [OrphanedContainerItem]?
    let scope: String?
    let installedAppScanStatus: String
    let installedAppScanError: String
    let containerIndexScanStatus: String
    let containerIndexScanError: String
    let orphanScanStatus: String

    private enum CodingKeys: String, CodingKey {
        case ok, apps, orphanedContainerCount, orphanedContainers, scope
        case installedAppScanStatus, installedAppScanError, containerIndexScanStatus
        case containerIndexScanError, orphanScanStatus
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ok = try values.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        apps = try values.decodeIfPresent([AppMaintenanceItem].self, forKey: .apps) ?? []
        orphanedContainerCount = try values.decodeIfPresent(Int.self, forKey: .orphanedContainerCount) ?? 0
        orphanedContainers = try values.decodeIfPresent([OrphanedContainerItem].self, forKey: .orphanedContainers)
        scope = try values.decodeIfPresent(String.self, forKey: .scope)
        installedAppScanStatus = try values.decodeIfPresent(String.self, forKey: .installedAppScanStatus) ?? "unknown"
        installedAppScanError = try values.decodeIfPresent(String.self, forKey: .installedAppScanError) ?? ""
        containerIndexScanStatus = try values.decodeIfPresent(String.self, forKey: .containerIndexScanStatus) ?? "unknown"
        containerIndexScanError = try values.decodeIfPresent(String.self, forKey: .containerIndexScanError) ?? ""
        orphanScanStatus = try values.decodeIfPresent(String.self, forKey: .orphanScanStatus) ?? "unknown"
    }
}
