import XCTest
@testable import Sappho

final class AuthRepositoryTests: XCTestCase {

    private var repo: AuthRepository!

    override func setUp() {
        super.setUp()
        repo = AuthRepository()
        // Clear any stored state from previous tests
        repo.clear()
    }

    override func tearDown() {
        repo.clear()
        repo = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateNotAuthenticated() {
        // After clearing, should not be authenticated
        repo.clear()
        let freshRepo = AuthRepository()
        // Since we just cleared the keychain, it should start unauthenticated
        // (unless there are leftover keychain items from the running app)
        // We test the property logic instead
        XCTAssertFalse(freshRepo.isAuthenticated)
        freshRepo.clear()
    }

    func testIsAuthenticatedRequiresBothTokenAndURL() {
        // After clearing, both are nil
        repo.clear()
        XCTAssertFalse(repo.isAuthenticated)

        // Store credentials to make it authenticated
        let url = URL(string: "https://example.com")!
        let user = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        repo.store(serverURL: url, token: "token123", user: user)
        XCTAssertTrue(repo.isAuthenticated)
    }

    // MARK: - Store and Retrieve

    func testStoreCredentials() {
        let url = URL(string: "https://sappho.example.com")!
        let user = makeLoginUser(id: 42, username: "testuser", isAdmin: 0)

        repo.store(serverURL: url, token: "my-token-abc", user: user)

        XCTAssertEqual(repo.serverURL, url)
        XCTAssertEqual(repo.token, "my-token-abc")
        XCTAssertEqual(repo.currentLoginUser?.id, 42)
        XCTAssertEqual(repo.currentLoginUser?.username, "testuser")
        XCTAssertTrue(repo.isAuthenticated)
    }

    func testStoreClearsCurrentUser() {
        // First set a full user profile
        let profileUser = makeUser(id: 1, username: "test", isAdmin: 0)
        repo.updateUser(profileUser)
        XCTAssertNotNil(repo.currentUser)

        // Storing new login credentials should clear currentUser
        let url = URL(string: "https://example.com")!
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        repo.store(serverURL: url, token: "token", user: loginUser)

        XCTAssertNil(repo.currentUser)
    }

    // MARK: - Update User

    func testUpdateUser() {
        let user = makeUser(id: 5, username: "mondo", isAdmin: 1)
        repo.updateUser(user)

        XCTAssertEqual(repo.currentUser?.id, 5)
        XCTAssertEqual(repo.currentUser?.username, "mondo")
        XCTAssertTrue(repo.currentUser?.isAdminUser ?? false)
    }

    // MARK: - Clear

    func testClearRemovesAllCredentials() {
        let url = URL(string: "https://sappho.test.com")!
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        let fullUser = makeUser(id: 1, username: "test", isAdmin: 0)

        repo.store(serverURL: url, token: "secret-token", user: loginUser)
        repo.updateUser(fullUser)

        XCTAssertTrue(repo.isAuthenticated)

        repo.clear()

        XCTAssertNil(repo.serverURL)
        XCTAssertNil(repo.token)
        XCTAssertNil(repo.currentUser)
        XCTAssertNil(repo.currentLoginUser)
        XCTAssertFalse(repo.isAuthenticated)
    }

    // MARK: - isAdmin

    func testIsAdminFromLoginUser() {
        let url = URL(string: "https://example.com")!
        let adminUser = makeLoginUser(id: 1, username: "admin", isAdmin: 1)

        repo.store(serverURL: url, token: "token", user: adminUser)

        XCTAssertTrue(repo.isAdmin)
    }

    func testIsAdminFromCurrentUser() {
        let url = URL(string: "https://example.com")!
        let loginUser = makeLoginUser(id: 1, username: "user", isAdmin: 0)
        repo.store(serverURL: url, token: "token", user: loginUser)

        // Login user is not admin
        XCTAssertFalse(repo.isAdmin)

        // But profile user is admin (overrides)
        let profileUser = makeUser(id: 1, username: "user", isAdmin: 1)
        repo.updateUser(profileUser)

        XCTAssertTrue(repo.isAdmin)
    }

    func testIsAdminDefaultsFalse() {
        repo.clear()
        XCTAssertFalse(repo.isAdmin)
    }

    // MARK: - Persistence

    func testCredentialsPersistAcrossInstances() {
        let url = URL(string: "https://persist.test.com")!
        let loginUser = makeLoginUser(id: 99, username: "persist", isAdmin: 0)

        repo.store(serverURL: url, token: "persist-token", user: loginUser)

        // Create a new instance (simulates app restart)
        let freshRepo = AuthRepository()

        XCTAssertEqual(freshRepo.serverURL, url)
        XCTAssertEqual(freshRepo.token, "persist-token")
        XCTAssertEqual(freshRepo.currentLoginUser?.id, 99)
        XCTAssertTrue(freshRepo.isAuthenticated)

        // Clean up
        freshRepo.clear()
    }

    func testClearPreventsRestorationOnNewInstance() {
        let url = URL(string: "https://example.com")!
        let loginUser = makeLoginUser(id: 1, username: "user", isAdmin: 0)

        repo.store(serverURL: url, token: "token", user: loginUser)
        repo.clear()

        let freshRepo = AuthRepository()
        XCTAssertFalse(freshRepo.isAuthenticated)
        XCTAssertNil(freshRepo.serverURL)
        XCTAssertNil(freshRepo.token)
    }

    // MARK: - Helpers

    /// Creates a LoginUser by encoding/decoding JSON, since LoginUser may not have a public memberwise init.
    private func makeLoginUser(id: Int, username: String, isAdmin: Int) -> LoginUser {
        let json = """
        {"id": \(id), "username": "\(username)", "is_admin": \(isAdmin)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LoginUser.self, from: json)
    }

    /// Creates a User by encoding/decoding JSON.
    private func makeUser(id: Int, username: String, isAdmin: Int) -> User {
        let json = """
        {"id": \(id), "username": "\(username)", "is_admin": \(isAdmin)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(User.self, from: json)
    }
}
