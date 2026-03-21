import XCTest
@testable import Sappho

final class SapphoAPIExtendedTests: XCTestCase {
    private var authRepo: AuthRepository!
    private var api: SapphoAPI!
    private var session: URLSession!
    private let testServerURL = URL(string: "https://sappho.test.com")!
    private let testToken = "test-token-abc123"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        authRepo = AuthRepository()
        authRepo.clear()
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        authRepo.store(serverURL: testServerURL, token: testToken, user: loginUser)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        api = SapphoAPI(authRepository: authRepo, session: session)
    }

    override func tearDown() {
        authRepo.clear()
        MockURLProtocol.reset()
        authRepo = nil
        api = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Collections

    func testGetCollections() async throws {
        let responseJSON = """
        [
            {"id": 1, "name": "Sci-Fi Favorites", "description": "Best sci-fi books", "user_id": 1, "book_count": 3, "is_public": 0, "created_at": "2025-01-01"},
            {"id": 2, "name": "To Read", "description": null, "user_id": 1, "book_count": 5, "is_public": 1, "created_at": "2025-02-01"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let collections = try await api.getCollections()
        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(collections[0].name, "Sci-Fi Favorites")
        XCTAssertEqual(collections[1].bookCount, 5)
    }

    func testGetCollection() async throws {
        let responseJSON = """
        {
            "id": 1, "name": "Sci-Fi Favorites", "description": "Best sci-fi", "user_id": 1,
            "is_public": 0, "created_at": "2025-01-01", "updated_at": "2025-03-01",
            "books": [
                {"id": 10, "title": "Dune", "file_count": 1, "created_at": "2025-01-01", "is_favorite": false}
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections/1") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let detail = try await api.getCollection(id: 1)
        XCTAssertEqual(detail.id, 1)
        XCTAssertEqual(detail.name, "Sci-Fi Favorites")
        XCTAssertEqual(detail.books.count, 1)
        XCTAssertEqual(detail.books[0].title, "Dune")
    }

    func testCreateCollection() async throws {
        let responseJSON = """
        {"id": 3, "name": "Horror", "description": "Scary stuff", "user_id": 1, "is_public": 1, "created_at": "2025-03-21"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["name"] as? String, "Horror")
                XCTAssertEqual(json?["description"] as? String, "Scary stuff")
                XCTAssertEqual(json?["is_public"] as? Bool, true)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let collection = try await api.createCollection(name: "Horror", description: "Scary stuff", isPublic: true)
        XCTAssertEqual(collection.id, 3)
        XCTAssertEqual(collection.name, "Horror")
    }

    func testDeleteCollection() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections/3") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.deleteCollection(id: 3)
    }

    func testAddToCollection() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections/1/items") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["audiobook_id"] as? Int, 42)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.addToCollection(collectionId: 1, audiobookId: 42)
    }

    func testRemoveFromCollection() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections/1/items/42") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.removeFromCollection(collectionId: 1, audiobookId: 42)
    }

    func testGetCollectionsForBook() async throws {
        let responseJSON = """
        [
            {"id": 1, "name": "Sci-Fi", "is_public": 0, "user_id": 1, "contains_book": 1},
            {"id": 2, "name": "To Read", "is_public": 1, "user_id": 1, "contains_book": 0}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/collections/for-book/42") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let collections = try await api.getCollectionsForBook(audiobookId: 42)
        XCTAssertEqual(collections.count, 2)
        XCTAssertTrue(collections[0].isInCollection)
        XCTAssertFalse(collections[1].isInCollection)
    }

    // MARK: - Ratings

    func testGetUserRating() async throws {
        let responseJSON = """
        {"id": 1, "user_id": 1, "audiobook_id": 42, "rating": 4, "review": "Great book!", "created_at": "2025-01-15", "updated_at": "2025-01-15"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/ratings/audiobook/42") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let rating = try await api.getUserRating(audiobookId: 42)
        XCTAssertEqual(rating?.rating, 4)
        XCTAssertEqual(rating?.review, "Great book!")
    }

    func testGetAverageRating() async throws {
        let responseJSON = """
        {"average": 4.5, "count": 12}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/ratings/audiobook/42/average") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let avg = try await api.getAverageRating(audiobookId: 42)
        XCTAssertEqual(avg.average, 4.5)
        XCTAssertEqual(avg.count, 12)
    }

    func testSetRating() async throws {
        let responseJSON = """
        {"id": 5, "user_id": 1, "audiobook_id": 42, "rating": 5, "review": "Masterpiece", "created_at": "2025-03-21", "updated_at": "2025-03-21"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/ratings/audiobook/42") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["rating"] as? Int, 5)
                XCTAssertEqual(json?["review"] as? String, "Masterpiece")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let rating = try await api.setRating(audiobookId: 42, rating: 5, review: "Masterpiece")
        XCTAssertEqual(rating.rating, 5)
        XCTAssertEqual(rating.review, "Masterpiece")
    }

    func testGetAllRatings() async throws {
        let responseJSON = """
        [
            {"id": 1, "user_id": 1, "audiobook_id": 42, "rating": 5, "review": "Amazing", "username": "alice", "display_name": "Alice", "created_at": "2025-01-01"},
            {"id": 2, "user_id": 2, "audiobook_id": 42, "rating": 3, "review": null, "username": "bob", "display_name": null, "created_at": "2025-02-01"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/ratings/audiobook/42/all") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let reviews = try await api.getAllRatings(audiobookId: 42)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0].username, "alice")
        XCTAssertEqual(reviews[0].rating, 5)
        XCTAssertEqual(reviews[1].rating, 3)
    }

    // MARK: - Profile

    func testGetProfile() async throws {
        let responseJSON = """
        {"id": 1, "username": "mondo", "email": "mondo@example.com", "display_name": "Mondo", "is_admin": 1, "avatar": "avatar.jpg", "created_at": "2024-06-01"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/profile") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let user = try await api.getProfile()
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.username, "mondo")
        XCTAssertEqual(user.displayName, "Mondo")
        XCTAssertTrue(user.isAdminUser)
    }

    func testGetProfileStats() async throws {
        let responseJSON = """
        {
            "totalListenTime": 36000,
            "booksStarted": 15,
            "booksCompleted": 8,
            "currentlyListening": 3,
            "topAuthors": [{"author": "Brandon Sanderson", "listenTime": 12000, "bookCount": 4}],
            "topGenres": [{"genre": "Fantasy", "listenTime": 18000, "bookCount": 6}],
            "recentActivity": [],
            "activeDaysLast30": 22,
            "currentStreak": 7,
            "avgSessionLength": 45.5
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/profile/stats") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let stats = try await api.getProfileStats()
        XCTAssertEqual(stats.totalListenTime, 36000)
        XCTAssertEqual(stats.booksCompleted, 8)
        XCTAssertEqual(stats.currentStreak, 7)
        XCTAssertEqual(stats.topAuthors.count, 1)
        XCTAssertEqual(stats.topAuthors[0].author, "Brandon Sanderson")
    }

    func testUpdateProfile() async throws {
        let responseJSON = """
        {"id": 1, "username": "mondo", "email": "new@example.com", "display_name": "New Name", "is_admin": 0, "created_at": "2024-06-01"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.absoluteString.contains("api/profile") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["displayName"] as? String, "New Name")
                XCTAssertEqual(json?["email"] as? String, "new@example.com")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let user = try await api.updateProfile(displayName: "New Name", email: "new@example.com")
        XCTAssertEqual(user.displayName, "New Name")
        XCTAssertEqual(user.email, "new@example.com")
    }

    func testUpdatePassword() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.absoluteString.contains("api/profile/password") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["currentPassword"] as? String, "oldpass")
                XCTAssertEqual(json?["newPassword"] as? String, "newpass123")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.updatePassword(currentPassword: "oldpass", newPassword: "newpass123")
    }

    func testDeleteAvatar() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/profile/avatar") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.deleteAvatar()
    }

    // MARK: - Notifications

    func testGetNotifications() async throws {
        let responseJSON = """
        [
            {"id": 1, "type": "new_book", "title": "New Book Added", "message": "Dune has been added to the library", "metadata": null, "created_at": "2025-03-20", "is_read": 0},
            {"id": 2, "type": "system", "title": "Update Available", "message": "Server v2.1 is available", "metadata": null, "created_at": "2025-03-19", "is_read": 1}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/notifications") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=50") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let notifications = try await api.getNotifications()
        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(notifications[0].title, "New Book Added")
        XCTAssertTrue(notifications[0].isUnread)
        XCTAssertFalse(notifications[1].isUnread)
    }

    func testGetUnreadNotificationCount() async throws {
        let responseJSON = """
        {"count": 5}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/notifications/unread-count") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let unread = try await api.getUnreadNotificationCount()
        XCTAssertEqual(unread.count, 5)
    }

    func testMarkNotificationRead() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/notifications/7/read") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.markNotificationRead(id: 7)
    }

    func testMarkAllNotificationsRead() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/notifications/read-all") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.markAllNotificationsRead()
    }

    // MARK: - AI / Recap

    func testGetAiStatus() async throws {
        let responseJSON = """
        {"configured": true}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/settings/ai/status") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let status = try await api.getAiStatus()
        XCTAssertTrue(status.configured)
    }

    func testGetAudiobookRecap() async throws {
        let responseJSON = """
        {
            "recap": "In the previous chapters, Paul arrived on Arrakis...",
            "cached": true,
            "cached_at": "2025-03-20T10:00:00Z",
            "priorBooks": [{"id": 1, "title": "Prelude to Dune", "position": 1.0}]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/recap") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let recap = try await api.getAudiobookRecap(audiobookId: 42)
        XCTAssertTrue(recap.recap.contains("Paul arrived on Arrakis"))
        XCTAssertEqual(recap.cached, true)
        XCTAssertEqual(recap.priorBooks?.count, 1)
    }

    func testClearAudiobookRecap() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/recap") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.clearAudiobookRecap(audiobookId: 42)
    }

    func testGetPreviousBookStatus() async throws {
        let responseJSON = """
        {
            "previous_book_completed": false,
            "previous_book": {"id": 10, "title": "Dune: Book 1", "series_position": 1.0}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/previous-book-status") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let status = try await api.getPreviousBookStatus(audiobookId: 42)
        XCTAssertFalse(status.previousBookCompleted)
        XCTAssertEqual(status.previousBook?.title, "Dune: Book 1")
        XCTAssertEqual(status.previousBook?.seriesPosition, 1.0)
    }

    func testGetSeriesRecap() async throws {
        let responseJSON = """
        {
            "recap": "The Dune saga follows the Atreides family...",
            "cached": false,
            "cached_at": null,
            "books_included": [
                {"id": 1, "title": "Dune", "position": 1.0},
                {"id": 2, "title": "Dune Messiah", "position": 2.0}
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/series/") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("/recap") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let recap = try await api.getSeriesRecap(seriesName: "Dune")
        XCTAssertTrue(recap.recap.contains("Atreides"))
        XCTAssertFalse(recap.cached)
        XCTAssertEqual(recap.booksIncluded.count, 2)
        XCTAssertEqual(recap.booksIncluded[0].title, "Dune")
    }

    // MARK: - Admin

    func testGetUsers() async throws {
        let responseJSON = """
        [
            {"id": 1, "username": "admin", "email": "admin@example.com", "is_admin": 1, "created_at": "2024-01-01", "last_login": "2025-03-21"},
            {"id": 2, "username": "reader", "email": null, "is_admin": 0, "created_at": "2024-06-15", "last_login": "2025-03-20", "is_disabled": 0}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/users") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let users = try await api.getUsers()
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].username, "admin")
        XCTAssertTrue(users[0].isAdminUser)
        XCTAssertFalse(users[1].isAdminUser)
    }

    func testCreateUser() async throws {
        let responseJSON = """
        {"id": 3, "username": "newuser", "email": null, "is_admin": 0, "created_at": "2025-03-21"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/users") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["username"] as? String, "newuser")
                XCTAssertEqual(json?["password"] as? String, "secret123")
                XCTAssertEqual(json?["is_admin"] as? Bool, false)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let user = try await api.createUser(username: "newuser", password: "secret123", isAdmin: false)
        XCTAssertEqual(user.id, 3)
        XCTAssertEqual(user.username, "newuser")
        XCTAssertFalse(user.isAdminUser)
    }

    func testDeleteUser() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/users/3") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.deleteUser(id: 3)
    }

    func testScanLibrary() async throws {
        let responseJSON = """
        {"message": "Scan complete", "new_books": 5, "total_books": 42}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/maintenance/scan") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await api.scanLibrary()
        XCTAssertEqual(result.message, "Scan complete")
        XCTAssertEqual(result.newBooks, 5)
        XCTAssertEqual(result.totalBooks, 42)
    }

    // MARK: - Library Browsing

    func testGetGenres() async throws {
        let responseJSON = """
        [
            {"genre": "Fantasy", "count": 25, "cover_ids": [1, 2, 3], "color": "#8B5CF6", "icon": "wand.and.stars"},
            {"genre": "Science Fiction", "count": 18, "cover_ids": [4, 5], "color": "#3B82F6"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/genres") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let genres = try await api.getGenres()
        XCTAssertEqual(genres.count, 2)
        XCTAssertEqual(genres[0].genre, "Fantasy")
        XCTAssertEqual(genres[0].count, 25)
        XCTAssertEqual(genres[0].coverIds, [1, 2, 3])
    }

    func testGetSeries() async throws {
        let responseJSON = """
        [
            {"series": "The Stormlight Archive", "book_count": 4, "cover_ids": ["1", "2", "3", "4"]},
            {"series": "Mistborn", "book_count": 6, "cover_ids": ["5", "6"]}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/series") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let series = try await api.getSeries()
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].series, "The Stormlight Archive")
        XCTAssertEqual(series[0].bookCount, 4)
        XCTAssertEqual(series[0].coverIds, [1, 2, 3, 4])
    }

    func testGetAuthors() async throws {
        let responseJSON = """
        [
            {"author": "Brandon Sanderson", "book_count": 10, "cover_ids": ["1", "2"]},
            {"author": "Frank Herbert", "book_count": 6, "cover_ids": ["3"]}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/authors") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let authors = try await api.getAuthors()
        XCTAssertEqual(authors.count, 2)
        XCTAssertEqual(authors[0].author, "Brandon Sanderson")
        XCTAssertEqual(authors[0].bookCount, 10)
    }

    func testGetAudiobooksByGenre() async throws {
        let responseJSON = """
        {"audiobooks": [{"id": 1, "title": "The Way of Kings", "genre": "Fantasy", "file_count": 1, "created_at": "2025-01-01", "is_favorite": false}]}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("genre=Fantasy") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getAudiobooksByGenre("Fantasy")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "The Way of Kings")
    }

    func testGetAudiobooksBySeries() async throws {
        let responseJSON = """
        {"audiobooks": [{"id": 5, "title": "Dune", "series": "Dune Chronicles", "file_count": 1, "created_at": "2025-01-01", "is_favorite": true}]}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("series=Dune") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getAudiobooksBySeries("Dune")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Dune")
        XCTAssertTrue(books[0].isFavorite)
    }

    func testGetAudiobooksByAuthor() async throws {
        let responseJSON = """
        {"audiobooks": [
            {"id": 1, "title": "Mistborn", "author": "Brandon Sanderson", "file_count": 1, "created_at": "2025-01-01", "is_favorite": false},
            {"id": 2, "title": "Elantris", "author": "Brandon Sanderson", "file_count": 1, "created_at": "2025-02-01", "is_favorite": false}
        ]}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("author=Brandon") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getAudiobooksByAuthor("Brandon Sanderson")
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].title, "Mistborn")
        XCTAssertEqual(books[1].title, "Elantris")
    }

    // MARK: - Favorites

    func testGetFavorites() async throws {
        let responseJSON = """
        [
            {"id": 10, "title": "Dune", "file_count": 1, "created_at": "2025-01-01", "is_favorite": true},
            {"id": 20, "title": "Neuromancer", "file_count": 1, "created_at": "2025-02-01", "is_favorite": true}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/favorites") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("sort=custom") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let favorites = try await api.getFavorites()
        XCTAssertEqual(favorites.count, 2)
        XCTAssertEqual(favorites[0].title, "Dune")
        XCTAssertTrue(favorites[0].isFavorite)
    }

    func testRemoveFavorite() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/10/favorite") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.removeFavorite(audiobookId: 10)
    }

    // MARK: - Progress

    func testGetProgress() async throws {
        let responseJSON = """
        {"id": 1, "user_id": 1, "audiobook_id": 42, "position": 3600, "completed": 0, "last_listened": "2025-03-21T10:00:00Z", "updated_at": "2025-03-21T10:00:00Z", "current_chapter": 5}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/progress") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let progress = try await api.getProgress(audiobookId: 42)
        XCTAssertEqual(progress.position, 3600)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertFalse(progress.isCompleted)
        XCTAssertEqual(progress.currentChapter, 5)
    }

    func testClearProgress() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/progress") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.clearProgress(audiobookId: 42)
    }

    // MARK: - Other: Meta Endpoints

    func testGetInProgress() async throws {
        let responseJSON = """
        [
            {"id": 1, "title": "Currently Reading", "file_count": 1, "created_at": "2025-01-01", "is_favorite": false, "progress": {"position": 1200, "completed": 0}}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/in-progress") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=10") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getInProgress()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Currently Reading")
        XCTAssertEqual(books[0].progress?.position, 1200)
    }

    func testGetFinished() async throws {
        let responseJSON = """
        [
            {"id": 5, "title": "Finished Book", "file_count": 1, "created_at": "2025-01-01", "is_favorite": false, "progress": {"position": 0, "completed": 1}}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/finished") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=10") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getFinished()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Finished Book")
        XCTAssertTrue(books[0].progress?.isCompleted ?? false)
    }

    func testGetUpNext() async throws {
        let responseJSON = """
        [
            {"id": 7, "title": "Up Next Book", "file_count": 1, "created_at": "2025-02-01", "is_favorite": false}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/up-next") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=10") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getUpNext()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Up Next Book")
    }

    func testGetAudiobook() async throws {
        let responseJSON = """
        {"id": 42, "title": "Dune", "author": "Frank Herbert", "narrator": "Scott Brick", "series": "Dune Chronicles", "series_position": 1.0, "duration": 79200, "genre": "Science Fiction", "file_count": 1, "created_at": "2025-01-01", "is_favorite": true}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let book = try await api.getAudiobook(id: 42)
        XCTAssertEqual(book.id, 42)
        XCTAssertEqual(book.title, "Dune")
        XCTAssertEqual(book.author, "Frank Herbert")
        XCTAssertEqual(book.narrator, "Scott Brick")
        XCTAssertEqual(book.duration, 79200)
        XCTAssertTrue(book.isFavorite)
    }

    func testGetListeningSessions() async throws {
        let responseJSON = """
        {
            "sessions": [
                {"id": 1, "started_at": "2025-03-21T08:00:00Z", "stopped_at": "2025-03-21T09:00:00Z", "start_position": 0, "end_position": 3600, "device_name": "iPhone 15"},
                {"id": 2, "started_at": "2025-03-20T20:00:00Z", "stopped_at": "2025-03-20T21:30:00Z", "start_position": 3600, "end_position": 9000, "device_name": "iPad"}
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/sessions") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=50") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let sessions = try await api.getListeningSessions(audiobookId: 42)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].startPosition, 0)
        XCTAssertEqual(sessions[0].endPosition, 3600)
        XCTAssertEqual(sessions[0].deviceName, "iPhone 15")
        XCTAssertEqual(sessions[1].deviceName, "iPad")
    }

    // MARK: - Helpers

    private func makeLoginUser(id: Int, username: String, isAdmin: Int) -> LoginUser {
        let json = """
        {"id": \(id), "username": "\(username)", "is_admin": \(isAdmin)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LoginUser.self, from: json)
    }
}
