import Foundation
import Security

@Observable
class AuthRepository {
    private let keychain = KeychainService()
    private let defaults = UserDefaults.standard

    // UserDefaults keys (survives Keychain corruption)
    private let kServerURL = "sappho_serverURL"
    private let kCurrentUser = "sappho_currentUser"
    private let kCurrentLoginUser = "sappho_currentLoginUser"
    private let kMigrated = "sappho_migratedToSplitStorage"

    private(set) var serverURL: URL?
    private(set) var token: String?
    private(set) var refreshToken: String?
    private(set) var currentUser: User?
    private(set) var currentLoginUser: LoginUser?

    var isAuthenticated: Bool {
        token != nil && serverURL != nil
    }

    var isAdmin: Bool {
        currentUser?.isAdminUser ?? currentLoginUser?.isAdminUser ?? false
    }

    init() {
        migrateIfNeeded()
        loadStoredCredentials()
    }

    /// One-time migration: move server URL and user info from Keychain to UserDefaults.
    /// Token stays in Keychain (secure). Everything else moves to UserDefaults (resilient).
    private func migrateIfNeeded() {
        guard !defaults.bool(forKey: kMigrated) else { return }

        // Migrate server URL
        if let urlString = keychain.get("serverURL") {
            defaults.set(urlString, forKey: kServerURL)
            keychain.delete("serverURL")
        }

        // Migrate user data
        if let userData = keychain.getData("currentUser") {
            defaults.set(userData, forKey: kCurrentUser)
            keychain.delete("currentUser")
        }

        if let loginUserData = keychain.getData("currentLoginUser") {
            defaults.set(loginUserData, forKey: kCurrentLoginUser)
            keychain.delete("currentLoginUser")
        }

        defaults.set(true, forKey: kMigrated)
    }

    private func loadStoredCredentials() {
        // Server URL from UserDefaults (resilient)
        if let urlString = defaults.string(forKey: kServerURL), let url = URL(string: urlString) {
            serverURL = url
        }

        // Tokens from Keychain (secure)
        token = keychain.get("authToken")
        refreshToken = keychain.get("refreshToken")

        // User info from UserDefaults (resilient)
        if let userData = defaults.data(forKey: kCurrentUser) {
            currentUser = try? JSONDecoder().decode(User.self, from: userData)
        }
        if let loginUserData = defaults.data(forKey: kCurrentLoginUser) {
            currentLoginUser = try? JSONDecoder().decode(LoginUser.self, from: loginUserData)
        }
    }

    func store(serverURL: URL, token: String, refreshToken: String?, user: LoginUser) {
        self.serverURL = serverURL
        self.token = token
        self.refreshToken = refreshToken
        self.currentLoginUser = user
        self.currentUser = nil

        // Tokens in Keychain (secure)
        keychain.set(token, forKey: "authToken")
        if let refreshToken {
            keychain.set(refreshToken, forKey: "refreshToken")
        } else {
            keychain.delete("refreshToken")
        }

        // Everything else in UserDefaults (survives Keychain issues)
        defaults.set(serverURL.absoluteString, forKey: kServerURL)
        if let userData = try? JSONEncoder().encode(user) {
            defaults.set(userData, forKey: kCurrentLoginUser)
        }
    }

    /// Replace just the access + refresh tokens after a successful refresh.
    /// Refresh tokens rotate, so both are overwritten. Server URL and user
    /// info are left untouched.
    func updateTokens(token: String, refreshToken: String) {
        self.token = token
        self.refreshToken = refreshToken
        keychain.set(token, forKey: "authToken")
        keychain.set(refreshToken, forKey: "refreshToken")
    }

    func updateUser(_ user: User) {
        self.currentUser = user
        if let userData = try? JSONEncoder().encode(user) {
            defaults.set(userData, forKey: kCurrentUser)
        }
    }

    /// Clear only the auth token (called on 401 — session expired).
    /// Preserves server URL and user info so the login screen can
    /// pre-fill them instead of making the user re-enter everything.
    func clearToken() {
        token = nil
        refreshToken = nil
        keychain.delete("authToken")
        keychain.delete("refreshToken")
    }

    /// Full logout — wipes everything. Called when the user explicitly
    /// logs out from the settings screen.
    func clear() {
        serverURL = nil
        token = nil
        refreshToken = nil
        currentUser = nil
        currentLoginUser = nil

        keychain.delete("authToken")
        keychain.delete("refreshToken")
        defaults.removeObject(forKey: kServerURL)
        defaults.removeObject(forKey: kCurrentUser)
        defaults.removeObject(forKey: kCurrentLoginUser)
    }
}

// MARK: - Keychain Service
class KeychainService {
    private let service = "com.sappho.audiobooks"

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        setData(data, forKey: key)
    }

    func setData(_ data: Data, forKey key: String) {
        // Delete existing item first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
