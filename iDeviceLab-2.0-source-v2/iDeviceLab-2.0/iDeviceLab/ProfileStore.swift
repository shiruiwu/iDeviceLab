import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [DeviceProfile] = [] {
        didSet { persist() }
    }
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedProfileID") }
    }
    @Published var managedApps: [ManagedApp] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(managedApps) {
                UserDefaults.standard.set(data, forKey: "iDeviceLabManagedAppsV1")
            }
        }
    }

    private let storageKey = "iDeviceLabProfilesV1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data), !decoded.isEmpty {
            profiles = Self.normalized(decoded)
        } else {
            profiles = [DeviceProfile(name: "测试环境 A")]
        }
        if let data = UserDefaults.standard.data(forKey: "iDeviceLabManagedAppsV1"),
           let savedApps = try? JSONDecoder().decode([ManagedApp].self, from: data) {
            managedApps = savedApps
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

    func addManagedApp(name: String, bundleIdentifier: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanBundle.isEmpty, let profileID = selectedID,
              !managedApps.contains(where: { $0.bundleIdentifier.caseInsensitiveCompare(cleanBundle) == .orderedSame }) else { return }
        managedApps.append(ManagedApp(name: cleanName, bundleIdentifier: cleanBundle, profileID: profileID))
    }

    func updateManagedApp(_ app: ManagedApp) {
        guard let index = managedApps.firstIndex(where: { $0.id == app.id }) else { return }
        managedApps[index] = app
    }

    func deleteManagedApp(_ app: ManagedApp) {
        managedApps.removeAll { $0.id == app.id }
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
        try Self.validateProfiles(imported)
        profiles = imported
        selectedID = profiles.first?.id
    }

    /// Creates a complete, versioned backup of profiles, app-to-profile bindings and selection.
    func exportFullBackupData() throws -> Data {
        let archive = FullBackupArchive(schemaVersion: 1, createdAt: Date(), profiles: profiles, managedApps: managedApps, selectedID: selectedID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(archive)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let envelope = FullBackupEnvelope(format: "iDeviceLab.FullBackup", envelopeVersion: 1, sha256: digest, payload: payload)
        let output = JSONEncoder()
        output.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try output.encode(envelope)
    }

    /// Checks integrity and schema before changing any persisted state. Legacy schema-1 backups remain importable.
    func restoreFullBackup(from data: Data) throws {
        let archive = try decodeAndValidateBackup(data)
        let rollback = try exportFullBackupData()
        UserDefaults.standard.set(rollback, forKey: "iDeviceLabPreRestoreBackupV1")
        apply(archive)
    }

    func restorePreRestoreSnapshot() throws {
        guard let data = UserDefaults.standard.data(forKey: "iDeviceLabPreRestoreBackupV1") else {
            throw ProfileError.noRollbackSnapshot
        }
        let archive = try decodeAndValidateBackup(data)
        apply(archive)
    }

    private func decodeAndValidateBackup(_ data: Data) throws -> FullBackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: FullBackupArchive
        if let envelope = try? decoder.decode(FullBackupEnvelope.self, from: data),
           envelope.format == "iDeviceLab.FullBackup" {
            guard envelope.envelopeVersion == 1 else { throw ProfileError.unsupportedVersion }
            let actual = SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
            guard actual.caseInsensitiveCompare(envelope.sha256) == .orderedSame else {
                throw ProfileError.backupIntegrityFailure
            }
            archive = try decoder.decode(FullBackupArchive.self, from: envelope.payload)
        } else {
            archive = try decoder.decode(FullBackupArchive.self, from: data)
        }
        guard archive.schemaVersion == 1 else { throw ProfileError.unsupportedVersion }
        guard !archive.profiles.isEmpty else { throw ProfileError.emptyArchive }
        guard archive.profiles.count <= 100, archive.managedApps.count <= 500 else { throw ProfileError.tooManyProfiles }
        try Self.validateProfiles(archive.profiles)
        try Self.validateManagedApps(archive.managedApps, profiles: archive.profiles)
        return archive
    }

    private func apply(_ archive: FullBackupArchive) {
        profiles = Self.normalized(archive.profiles)
        managedApps = archive.managedApps
        let validIDs = Set(profiles.map(\.id))
        selectedID = archive.selectedID.flatMap { validIDs.contains($0) ? $0 : nil } ?? profiles[0].id
    }

    private static func validateProfiles(_ profiles: [DeviceProfile]) throws {
        let ids = profiles.map(\.id)
        guard Set(ids).count == ids.count else { throw ProfileError.duplicateIdentifiers }
        for profile in profiles {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  profile.latitude.isFinite, (-90...90).contains(profile.latitude),
                  profile.longitude.isFinite, (-180...180).contains(profile.longitude),
                  (1...100).contains(profile.batteryPercent),
                  (1...64).contains(profile.memoryGB),
                  !profile.testIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ProfileError.invalidProfile }
        }
    }

    private static func validateManagedApps(_ apps: [ManagedApp], profiles: [DeviceProfile]) throws {
        let appIDs = apps.map(\.id)
        guard Set(appIDs).count == appIDs.count else { throw ProfileError.duplicateManagedAppIdentifiers }
        let bundleIDs = apps.map { $0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(bundleIDs).count == bundleIDs.count else { throw ProfileError.duplicateBundleIdentifiers }
        let validProfileIDs = Set(profiles.map(\.id))
        for app in apps {
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validProfileIDs.contains(app.profileID) else { throw ProfileError.invalidManagedApp }
        }
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

struct FullBackupArchive: Codable {
    var schemaVersion: Int
    var createdAt: Date
    var profiles: [DeviceProfile]
    var managedApps: [ManagedApp]
    var selectedID: UUID?
}

private struct FullBackupEnvelope: Codable {
    var format: String
    var envelopeVersion: Int
    var sha256: String
    var payload: Data
}

enum ProfileError: LocalizedError {
    case unsupportedVersion, emptyArchive, tooManyProfiles, duplicateIdentifiers, duplicateManagedAppIdentifiers, duplicateBundleIdentifiers, invalidProfile, invalidManagedApp, noRollbackSnapshot, backupIntegrityFailure
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "不支持此配置文件版本"
        case .emptyArchive: return "配置文件中没有配置内容"
        case .tooManyProfiles: return "配置数量超出限制（最多 100 套配置、500 个应用绑定）"
        case .duplicateIdentifiers: return "备份包含重复的配置标识符"
        case .duplicateManagedAppIdentifiers: return "备份包含重复的应用绑定标识符"
        case .duplicateBundleIdentifiers: return "备份包含重复的应用 Bundle ID"
        case .invalidProfile: return "配置包含空名称、无效坐标或超出范围的测试数值"
        case .invalidManagedApp: return "备份包含无效的应用绑定或指向不存在的配置"
        case .noRollbackSnapshot: return "没有可用的还原前自动备份"
        case .backupIntegrityFailure: return "备份完整性校验失败，文件可能已损坏或被修改"
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
