import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [DeviceProfile] = [] {
        didSet { persist() }
    }
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedProfileID") }
    }

    private let storageKey = "iDeviceLabProfilesV1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data), !decoded.isEmpty {
            profiles = Self.normalized(decoded)
        } else {
            profiles = [DeviceProfile(name: "测试环境 A")]
        }
        if let raw = UserDefaults.standard.string(forKey: "selectedProfileID"),
           let id = UUID(uuidString: raw), profiles.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = profiles.first?.id
        }
    }

    var selectedProfile: DeviceProfile? {
        profiles.first(where: { $0.id == selectedID })
    }

    func update(_ profile: DeviceProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var copy = profile
        copy.latitude = min(90, max(-90, copy.latitude))
        copy.longitude = min(180, max(-180, copy.longitude))
        copy.batteryPercent = min(100, max(1, copy.batteryPercent))
        copy.updatedAt = Date()
        profiles[index] = copy
    }

    func addProfile() {
        let profile = DeviceProfile(name: "测试环境 \(profiles.count + 1)")
        profiles.append(profile)
        selectedID = profile.id
    }

    func duplicateSelected() {
        guard let current = selectedProfile, profiles.count < 100 else { return }
        var copy = current
        copy.id = UUID()
        copy.name = "\(current.name) - 副本"
        copy.testIdentifier = UUID().uuidString
        copy.updatedAt = Date()
        profiles.append(copy)
        selectedID = copy.id
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        profiles.removeAll { $0.id == id }
        if profiles.isEmpty { profiles = [DeviceProfile(name: "测试环境 A")] }
        selectedID = profiles.first?.id
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func randomizeAll() {
        guard var p = selectedProfile else { return }
        p.deviceModel = DeviceProfile.deviceModels.randomElement()!
        p.iosVersion = DeviceProfile.iosVersions.randomElement()!
        p.language = DeviceProfile.languages.randomElement()!
        p.region = DeviceProfile.regions.randomElement()!
        let zone = [("Asia/Shanghai", 31.2304, 121.4737), ("Asia/Tokyo", 35.6762, 139.6503),
                    ("America/New_York", 40.7128, -74.0060), ("Europe/London", 51.5072, -0.1276),
                    ("Asia/Seoul", 37.5665, 126.9780)].randomElement()!
        p.timeZone = zone.0
        p.latitude = zone.1 + Double.random(in: -0.08...0.08)
        p.longitude = zone.2 + Double.random(in: -0.08...0.08)
        p.network = DeviceProfile.networkTypes.randomElement()!
        p.batteryPercent = Int.random(in: 1...100)
        p.memoryGB = [2, 4, 6, 8, 12, 16].randomElement()!
        p.testIdentifier = UUID().uuidString
        update(p)
    }

    func randomize(_ field: String) {
        guard var p = selectedProfile else { return }
        switch field {
        case "deviceModel": p.deviceModel = DeviceProfile.deviceModels.randomElement()!
        case "iosVersion": p.iosVersion = DeviceProfile.iosVersions.randomElement()!
        case "language": p.language = DeviceProfile.languages.randomElement()!
        case "region": p.region = DeviceProfile.regions.randomElement()!
        case "timeZone": p.timeZone = DeviceProfile.timeZones.randomElement()!
        case "network": p.network = DeviceProfile.networkTypes.randomElement()!
        case "batteryPercent": p.batteryPercent = Int.random(in: 1...100)
        case "memoryGB": p.memoryGB = [2, 4, 6, 8, 12, 16].randomElement()!
        case "testIdentifier": p.testIdentifier = UUID().uuidString
        case "location":
            p.latitude = Double.random(in: -60...60)
            p.longitude = Double.random(in: -170...170)
        default: break
        }
        update(p)
    }

    func exportData() -> Data? {
        guard !profiles.isEmpty else { return nil }
        return try? JSONEncoder.pretty.encode(ProfileArchive(profiles: profiles))
    }

    func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported: [DeviceProfile]
        if let archive = try? decoder.decode(ProfileArchive.self, from: data) {
            guard archive.formatVersion == 1 else { throw ProfileError.unsupportedVersion }
            imported = archive.profiles
        } else {
            imported = try decoder.decode([DeviceProfile].self, from: data)
        }
        guard !imported.isEmpty else { throw ProfileError.emptyArchive }
        guard imported.count <= 100 else { throw ProfileError.tooManyProfiles }
        profiles = Self.normalized(imported)
        selectedID = profiles.first?.id
    }

    private static func normalized(_ input: [DeviceProfile]) -> [DeviceProfile] {
        var seen = Set<UUID>()
        return input.map { original in
            var item = original
            if !seen.insert(item.id).inserted { item.id = UUID(); seen.insert(item.id) }
            item.latitude = min(90, max(-90, item.latitude))
            item.longitude = min(180, max(-180, item.longitude))
            item.batteryPercent = min(100, max(1, item.batteryPercent))
            return item
        }
    }
}

enum ProfileError: LocalizedError {
    case unsupportedVersion, emptyArchive, tooManyProfiles
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "不支持此配置文件版本"
        case .emptyArchive: return "配置文件中没有配置内容"
        case .tooManyProfiles: return "单次最多导入 100 套配置"
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
