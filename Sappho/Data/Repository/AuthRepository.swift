import Foundation
import Security

@Observable
class AuthRepository {
    private let keychain = KeychainService()

    private(set) var serverURL: URL?
    private(set) var token: String?
    private(set) var currentUser: User?
    private(set) var currentLoginUser: LoginUser?

    var isAuthenticated: Bool {
        token != nil && serverURL != nil
    }

    var isAdmin: Bool {
        currentUser?.isAdminUser ?? currentLoginUser?.isAdminUser ?? false
    }

    init() {
        // Load stored credentials on init
        loadStoredCredentials()
    }

    private func loadStoredCredentials() {
        if let urlString = keychain.get("serverURL"), let url = URL(string: urlString) {
            serverURL = url
        }
        token = keychain.get("authToken")
        if let userData = keychain.getData("currentUser") {
            currentUser = try? JSONDecoder().decode(User.self, from: userData)
        }
        if let loginUserData = keychain.getData("currentLoginUser") {
            currentLoginUser = try? JSONDecoder().decode(LoginUser.self, from: loginUserData)
        }
    }

    func store(serverURL: URL, token: String, user: LoginUser) {
        self.serverURL = serverURL
        self.token = token
        self.currentLoginUser = user
        self.currentUser = nil // Will be loaded from profile later

        keychain.set(serverURL.absoluteString, forKey: "serverURL")
        keychain.set(token, forKey: "authToken")
        if let userData = try? JSONEncoder().encode(user) {
            keychain.setData(userData, forKey: "currentLoginUser")
        }
    }

    func updateUser(_ user: User) {
        self.currentUser = user
        if let userData = try? JSONEncoder().encode(user) {
            keychain.setData(userData, forKey: "currentUser")
        }
    }

    func clear() {
        serverURL = nil
        token = nil
        currentUser = nil
        currentLoginUser = nil

        keychain.delete("serverURL")
        keychain.delete("authToken")
        keychain.delete("currentUser")
        keychain.delete("currentLoginUser")
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
