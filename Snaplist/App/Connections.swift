import ArchiveCore
import Foundation
import Security

// MARK: Apple Pay taps

extension AppModel {
    /// A charge from the Shortcuts automation, on its card's statement.
    func logCharge(_ charge: LiveCharge, card: String?) throws {
        guard Pro.shared.isUnlocked else { throw ProRequired() }
        let name = card?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try archive.addLive([charge], feed: name.isEmpty ? "Apple Pay" : name, source: .tap)
        amountsChanged()
    }
}

// MARK: SimpleFIN

/// A SimpleFIN Bridge connection: the person links their banks on
/// SimpleFIN's site and pastes a setup token here. Snaplist trades it once
/// for an access URL, kept in the Keychain on this iPhone only, and reads
/// posted transactions with it. Read-only: SimpleFIN can't move money.
enum SimpleFIN {
    static let siteURL = URL(string: "https://bridge.simplefin.org")!
    private static let keychainAccount = "simplefin-access-url"
    static let lastSyncKey = "simplefinLastSync"
    static let accountsKey = "simplefinAccounts"

    enum Failure: LocalizedError {
        case badToken, claimFailed(Int), notConnected, server(String)

        var errorDescription: String? {
            switch self {
            case .badToken: "That isn't a SimpleFIN setup token. Copy the whole token from SimpleFIN Bridge and paste it again."
            case .claimFailed(403): "That setup token was already used. Make a new one in SimpleFIN Bridge and paste it here."
            case .claimFailed(let code): "SimpleFIN didn't accept the token (error \(code)). Try a new one."
            case .notConnected: "No bank is connected."
            case .server(let message): message
            }
        }
    }

    static var isConnected: Bool { accessURL != nil }

    static var lastSync: Date? {
        let value = UserDefaults.standard.double(forKey: lastSyncKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Trades a setup token for an access URL and keeps it.
    static func connect(setupToken: String) async throws {
        guard let claim = SimpleFINResponse.claimURL(fromSetupToken: setupToken) else { throw Failure.badToken }
        var request = URLRequest(url: claim)
        request.httpMethod = "POST"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let access = URL(string: text), access.scheme == "https" else { throw Failure.claimFailed(status) }
        try saveAccessURL(access.absoluteString)
    }

    static func disconnect() {
        SecItemDelete(keychainQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        UserDefaults.standard.removeObject(forKey: accountsKey)
    }

    /// Posted transactions since `start`, by account.
    static func fetch(since start: Date) async throws -> SimpleFINResponse {
        guard let accessString = accessURL, var components = URLComponents(string: accessString) else { throw Failure.notConnected }
        let user = components.percentEncodedUser ?? "", password = components.percentEncodedPassword ?? ""
        components.user = nil
        components.password = nil
        components.path = components.path.hasSuffix("/") ? components.path + "accounts" : components.path + "/accounts"
        components.queryItems = [URLQueryItem(name: "start-date", value: String(Int(start.timeIntervalSince1970)))]
        guard let url = components.url else { throw Failure.notConnected }
        var request = URLRequest(url: url)
        let credentials = Data("\(user.removingPercentEncoding ?? user):\(password.removingPercentEncoding ?? password)".utf8)
        request.setValue("Basic \(credentials.base64EncodedString())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 { throw Failure.server("SimpleFIN no longer accepts this connection. Disconnect and connect again with a new token.") }
        guard status == 200 else { throw Failure.server("SimpleFIN couldn't be reached (error \(status)). Try again later.") }
        return try JSONDecoder().decode(SimpleFINResponse.self, from: data)
    }

    // MARK: Keychain

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.rcabral.snaplist",
         kSecAttrAccount as String: keychainAccount]
    }

    private static var accessURL: String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveAccessURL(_ value: String) throws {
        SecItemDelete(keychainQuery as CFDictionary)
        var item = keychainQuery
        item[kSecValueData as String] = Data(value.utf8)
        // On this iPhone only, never in iCloud Keychain or a backup to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.server("Couldn't save the connection (\(status)).") }
    }
}

extension AppModel {
    /// Fetches new transactions. The first sync goes back 90 days; later ones
    /// overlap the last by a week, since banks post late. Returns how many
    /// charges were new.
    @discardableResult
    func syncBanks() async throws -> Int {
        let start = SimpleFIN.lastSync.map { $0.addingTimeInterval(-7 * 86_400) } ?? Date.now.addingTimeInterval(-90 * 86_400)
        let response = try await SimpleFIN.fetch(since: start)
        var added = 0
        for (feed, charges) in response.charges() where !charges.isEmpty {
            added += try archive.addLive(charges, feed: feed)
        }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: SimpleFIN.lastSyncKey)
        UserDefaults.standard.set(response.charges().map(\.feed), forKey: SimpleFIN.accountsKey)
        if added > 0 { amountsChanged() }
        if !response.errors.isEmpty, added == 0 {
            throw SimpleFIN.Failure.server(response.errors.joined(separator: " "))
        }
        return added
    }

    /// When the app comes forward, at most every six hours: SimpleFIN
    /// refreshes about once a day and limits how often it's asked.
    func syncBanksIfDue() {
        // Real charges never go into the sample archive.
        guard Pro.shared.isUnlocked, !DemoData.isEnabled else { return }
        // Apple Card is on the iPhone itself: every time, once a minute at most.
        if AppleCard.isEnabled, AppleCard.lastSync.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
            Task { try? await syncAppleCard() }
        }
        guard SimpleFIN.isConnected else { return }
        if let last = SimpleFIN.lastSync, Date.now.timeIntervalSince(last) < 6 * 3600 { return }
        Task { try? await syncBanks() }
    }
}

/// Live charges are part of Snaplist Pro.
struct ProRequired: LocalizedError {
    var errorDescription: String? { "Logging charges is part of Snaplist Pro. Open Snaplist to get it." }
}
