import Foundation
import OSLog

enum AppConfiguration {
    static let appGroup = "group.com.changqk.Sub2APIBoard"
    static let keychainService = "com.changqk.Sub2APIBoard.auth"
    static let sharedStoreKeychainService = "com.changqk.Sub2APIBoard.shared-store"
    static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    }
    static let legacyWidgetKind = "Sub2APIBoardWidget"
    static let widgetKind = "Sub2APIBoardWidget.v2"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

struct BoardSettings: Codable, Equatable {
    static let refreshMinuteOptions = [1, 5, 10] + Array(stride(from: 15, through: 60, by: 5))

    var serverURL = ""
    var selectedAccountIDs: [Int] = []
    var refreshMinutes = 15

    var effectiveRefreshMinutes: Int {
        Self.refreshMinuteOptions.contains(refreshMinutes) ? refreshMinutes : 15
    }

    var apiBaseURL: URL? {
        let raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              scheme == "https" || (scheme == "http" && Self.localHosts.contains(host)) else {
            return nil
        }
        components.scheme = scheme
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/api/v1") { path += "/api/v1" }
        components.path = path
        return components.url
    }

    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
}

enum SharedStore {
    private static let logger = Logger(subsystem: "com.changqk.Sub2APIBoard", category: "SharedStore")
    private static let settingsKey = "board.settings.v1"
    private static let snapshotKey = "board.snapshot.v1"
    private static let settingsFile = "board-settings-v1.json"
    private static let snapshotFile = "board-snapshot-v1.json"
    private static let settingsKeychainAccount = "settings.v1"
    private static let snapshotKeychainAccount = "snapshot.v1"

    static func loadSettings() -> BoardSettings {
        if let data = try? KeychainStore.loadSharedData(account: settingsKeychainAccount),
           let value = try? JSONDecoder.sub2api.decode(BoardSettings.self, from: data) {
            return value
        }
        if let value: BoardSettings = loadFile(named: settingsFile) {
            if let data = try? JSONEncoder.sub2api.encode(value) {
                try? KeychainStore.saveSharedData(data, account: settingsKeychainAccount)
            }
            return value
        }
        guard let data = AppConfiguration.defaults.data(forKey: settingsKey),
              let value = try? JSONDecoder.sub2api.decode(BoardSettings.self, from: data) else {
            return BoardSettings()
        }
        try? KeychainStore.saveSharedData(data, account: settingsKeychainAccount)
        try? writeFile(data, named: settingsFile)
        return value
    }

    static func saveSettings(_ settings: BoardSettings) throws {
        let data = try JSONEncoder.sub2api.encode(settings)
        try KeychainStore.saveSharedData(data, account: settingsKeychainAccount)
        try? writeFile(data, named: settingsFile)
        AppConfiguration.defaults.set(data, forKey: settingsKey)
        AppConfiguration.defaults.synchronize()
    }

    static func loadSnapshot() -> BoardSnapshot? {
        if let data = try? KeychainStore.loadSharedData(account: snapshotKeychainAccount),
           let value = try? JSONDecoder.sub2api.decode(BoardSnapshot.self, from: data) {
            return value
        }
        if let value: BoardSnapshot = loadFile(named: snapshotFile) {
            if let data = try? JSONEncoder.sub2api.encode(value) {
                try? KeychainStore.saveSharedData(data, account: snapshotKeychainAccount)
            }
            return value
        }
        guard let data = AppConfiguration.defaults.data(forKey: snapshotKey),
              let value = try? JSONDecoder.sub2api.decode(BoardSnapshot.self, from: data) else {
            return nil
        }
        try? KeychainStore.saveSharedData(data, account: snapshotKeychainAccount)
        try? writeFile(data, named: snapshotFile)
        return value
    }

    static func saveSnapshot(_ snapshot: BoardSnapshot) throws {
        let data = try JSONEncoder.sub2api.encode(snapshot)
        try KeychainStore.saveSharedData(data, account: snapshotKeychainAccount)
        try? writeFile(data, named: snapshotFile)
        AppConfiguration.defaults.set(data, forKey: snapshotKey)
        AppConfiguration.defaults.synchronize()
    }

    static func clearSnapshot() {
        KeychainStore.clearSharedData(account: snapshotKeychainAccount)
        if let url = sharedFileURL(named: snapshotFile) {
            try? FileManager.default.removeItem(at: url)
        }
        AppConfiguration.defaults.removeObject(forKey: snapshotKey)
        AppConfiguration.defaults.synchronize()
    }

    private static func loadFile<Value: Decodable>(named name: String) -> Value? {
        guard let url = sharedFileURL(named: name) else {
            logger.error("App Group container URL is unavailable for \(name, privacy: .public)")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Cannot read \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder.sub2api.decode(Value.self, from: data)
        } catch {
            logger.error("Cannot decode \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func writeFile(_ data: Data, named name: String) throws {
        guard let url = sharedFileURL(named: name) else { return }
        try data.write(to: url, options: .atomic)
    }

    private static func sharedFileURL(named name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroup)?
            .appendingPathComponent(name, isDirectory: false)
    }
}

extension JSONDecoder {
    static var sub2api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid RFC3339 date: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    static var sub2api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
