import XCTest
@testable import Sappho

final class ModelsTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Audiobook Decoding

    func testAudiobookDecodesFullJSON() throws {
        let json = """
        {
            "id": 42,
            "title": "The Great Gatsby",
            "subtitle": "A Novel",
            "author": "F. Scott Fitzgerald",
            "narrator": "Jake Gyllenhaal",
            "series": "Classics",
            "series_position": 1.0,
            "series_index": 1.0,
            "duration": 18000,
            "genre": "Fiction",
            "normalized_genre": "fiction",
            "tags": "classic,american",
            "published_year": 1925,
            "copyright_year": 1925,
            "publisher": "Scribner",
            "isbn": "978-0743273565",
            "asin": "B000FC0PDA",
            "language": "English",
            "rating": 4.5,
            "user_rating": 5.0,
            "average_rating": 4.2,
            "abridged": 0,
            "description": "A story of the Jazz Age.",
            "cover_image": "cover.jpg",
            "file_count": 3,
            "is_multi_file": 1,
            "created_at": "2024-01-15T10:30:00Z",
            "is_favorite": true,
            "is_queued": false,
            "last_played": "2024-06-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)

        XCTAssertEqual(book.id, 42)
        XCTAssertEqual(book.title, "The Great Gatsby")
        XCTAssertEqual(book.subtitle, "A Novel")
        XCTAssertEqual(book.author, "F. Scott Fitzgerald")
        XCTAssertEqual(book.narrator, "Jake Gyllenhaal")
        XCTAssertEqual(book.series, "Classics")
        XCTAssertEqual(book.seriesPosition, 1.0)
        XCTAssertEqual(book.seriesIndex, 1.0)
        XCTAssertEqual(book.duration, 18000)
        XCTAssertEqual(book.genre, "Fiction")
        XCTAssertEqual(book.normalizedGenre, "fiction")
        XCTAssertEqual(book.tags, "classic,american")
        XCTAssertEqual(book.publishYear, 1925)
        XCTAssertEqual(book.copyrightYear, 1925)
        XCTAssertEqual(book.publisher, "Scribner")
        XCTAssertEqual(book.isbn, "978-0743273565")
        XCTAssertEqual(book.asin, "B000FC0PDA")
        XCTAssertEqual(book.language, "English")
        XCTAssertEqual(book.rating, 4.5)
        XCTAssertEqual(book.userRating, 5.0)
        XCTAssertEqual(book.averageRating, 4.2)
        XCTAssertEqual(book.abridged, 0)
        XCTAssertEqual(book.description, "A story of the Jazz Age.")
        XCTAssertEqual(book.coverImage, "cover.jpg")
        XCTAssertEqual(book.fileCount, 3)
        XCTAssertEqual(book.isMultiFile, 1)
        XCTAssertEqual(book.createdAt, "2024-01-15T10:30:00Z")
        XCTAssertTrue(book.isFavorite)
        XCTAssertEqual(book.isQueued, false)
        XCTAssertEqual(book.lastPlayed, "2024-06-01T12:00:00Z")
    }

    func testAudiobookDecodesMinimalJSON() throws {
        let json = """
        {
            "id": 1,
            "title": "Minimal Book"
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)

        XCTAssertEqual(book.id, 1)
        XCTAssertEqual(book.title, "Minimal Book")
        XCTAssertNil(book.subtitle)
        XCTAssertNil(book.author)
        XCTAssertNil(book.narrator)
        XCTAssertNil(book.series)
        XCTAssertNil(book.seriesPosition)
        XCTAssertNil(book.duration)
        XCTAssertNil(book.genre)
        XCTAssertNil(book.coverImage)
        XCTAssertEqual(book.fileCount, 1) // defaults to 1
        XCTAssertEqual(book.createdAt, "") // defaults to empty string
        XCTAssertNil(book.progress)
        XCTAssertNil(book.chapters)
        XCTAssertFalse(book.isFavorite) // defaults to false
        XCTAssertNil(book.isQueued)
        XCTAssertNil(book.lastPlayed)
    }

    func testAudiobookRatingDecodesFromString() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "rating": "3.7"
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertNotNil(book.rating)
        XCTAssertEqual(Double(book.rating!), 3.7, accuracy: 0.01)
    }

    func testAudiobookRatingDecodesFromFloat() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "rating": 4.5
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertNotNil(book.rating)
        XCTAssertEqual(Double(book.rating!), 4.5, accuracy: 0.01)
    }

    func testAudiobookRatingNullYieldsNil() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "rating": null
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertNil(book.rating)
    }

    func testAudiobookIsFavoriteFromInt() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "is_favorite": 1
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertTrue(book.isFavorite)
    }

    func testAudiobookIsFavoriteFromIntZero() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "is_favorite": 0
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertFalse(book.isFavorite)
    }

    func testAudiobookIsQueuedFromInt() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "is_queued": 1
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertEqual(book.isQueued, true)
    }

    func testAudiobookIsQueuedFromBool() throws {
        let json = """
        {
            "id": 1,
            "title": "Book",
            "is_queued": true
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)
        XCTAssertEqual(book.isQueued, true)
    }

    func testAudiobookEquality() {
        let book1 = Audiobook(id: 1, title: "Book A")
        let book2 = Audiobook(id: 1, title: "Book B")
        let book3 = Audiobook(id: 2, title: "Book A")

        XCTAssertEqual(book1, book2, "Audiobooks with same ID should be equal regardless of title")
        XCTAssertNotEqual(book1, book3, "Audiobooks with different IDs should not be equal")
    }

    func testAudiobookHashability() {
        let book1 = Audiobook(id: 5, title: "A")
        let book2 = Audiobook(id: 5, title: "B")

        var set = Set<Audiobook>()
        set.insert(book1)
        set.insert(book2)

        XCTAssertEqual(set.count, 1, "Same ID should produce same hash, so set should contain 1 element")
    }

    func testWithChaptersReturnsNewInstance() {
        let original = Audiobook(id: 1, title: "Book", author: "Author", duration: 3600)
        let chapters = [
            Chapter(id: 1, audiobookId: 1, chapterNumber: 1, startTime: 0, duration: 1800, title: "Ch 1"),
            Chapter(id: 2, audiobookId: 1, chapterNumber: 2, startTime: 1800, duration: 1800, title: "Ch 2"),
        ]

        let updated = original.withChapters(chapters)

        XCTAssertEqual(updated.id, 1)
        XCTAssertEqual(updated.title, "Book")
        XCTAssertEqual(updated.author, "Author")
        XCTAssertEqual(updated.duration, 3600)
        XCTAssertEqual(updated.chapters?.count, 2)
        XCTAssertNil(original.chapters)
    }

    // MARK: - Progress Decoding

    func testProgressDecodesFullJSON() throws {
        let json = """
        {
            "id": 10,
            "user_id": 2,
            "audiobook_id": 42,
            "position": 1500,
            "completed": 0,
            "last_listened": "2024-06-01T12:00:00Z",
            "updated_at": "2024-06-01T12:00:00Z",
            "current_chapter": 3
        }
        """.data(using: .utf8)!

        let progress = try decoder.decode(Progress.self, from: json)

        XCTAssertEqual(progress.id, 10)
        XCTAssertEqual(progress.userId, 2)
        XCTAssertEqual(progress.audiobookId, 42)
        XCTAssertEqual(progress.position, 1500)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertEqual(progress.lastListened, "2024-06-01T12:00:00Z")
        XCTAssertEqual(progress.updatedAt, "2024-06-01T12:00:00Z")
        XCTAssertEqual(progress.currentChapter, 3)
        XCTAssertFalse(progress.isCompleted)
    }

    func testProgressIsCompleted() throws {
        let json = """
        {
            "position": 0,
            "completed": 1
        }
        """.data(using: .utf8)!

        let progress = try decoder.decode(Progress.self, from: json)
        XCTAssertTrue(progress.isCompleted)
    }

    func testProgressDefaultsPositionAndCompleted() throws {
        let json = "{}".data(using: .utf8)!

        let progress = try decoder.decode(Progress.self, from: json)
        XCTAssertEqual(progress.position, 0)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertNil(progress.id)
        XCTAssertNil(progress.userId)
    }

    func testProgressMemberwiseInit() {
        let progress = Progress(position: 300, completed: 0)

        XCTAssertEqual(progress.position, 300)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertNil(progress.id)
        XCTAssertNil(progress.userId)
        XCTAssertNil(progress.audiobookId)
    }

    // MARK: - Chapter Decoding

    func testChapterDecodesFullJSON() throws {
        let json = """
        {
            "id": 100,
            "audiobook_id": 42,
            "chapter_number": 5,
            "file_path": "/audio/ch5.mp3",
            "start_time": 3600.5,
            "duration": 1200.0,
            "file_size": 15000000,
            "title": "The Party",
            "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let chapter = try decoder.decode(Chapter.self, from: json)

        XCTAssertEqual(chapter.id, 100)
        XCTAssertEqual(chapter.audiobookId, 42)
        XCTAssertEqual(chapter.chapterNumber, 5)
        XCTAssertEqual(chapter.filePath, "/audio/ch5.mp3")
        XCTAssertEqual(chapter.startTime, 3600.5, accuracy: 0.01)
        XCTAssertEqual(chapter.duration, 1200.0)
        XCTAssertEqual(chapter.fileSize, 15000000)
        XCTAssertEqual(chapter.title, "The Party")
        XCTAssertEqual(chapter.createdAt, "2024-01-01T00:00:00Z")
    }

    func testChapterDecodesMinimalJSON() throws {
        let json = """
        {
            "id": 1,
            "audiobook_id": 1
        }
        """.data(using: .utf8)!

        let chapter = try decoder.decode(Chapter.self, from: json)

        XCTAssertEqual(chapter.id, 1)
        XCTAssertEqual(chapter.audiobookId, 1)
        XCTAssertEqual(chapter.chapterNumber, 0) // defaults to 0
        XCTAssertEqual(chapter.startTime, 0) // defaults to 0
        XCTAssertNil(chapter.filePath)
        XCTAssertNil(chapter.duration)
        XCTAssertNil(chapter.fileSize)
        XCTAssertNil(chapter.title)
    }

    func testChapterMemberwiseInit() {
        let chapter = Chapter(id: 1, audiobookId: 10, chapterNumber: 3, startTime: 500.0, duration: 200.0, title: "Intro")

        XCTAssertEqual(chapter.id, 1)
        XCTAssertEqual(chapter.audiobookId, 10)
        XCTAssertEqual(chapter.chapterNumber, 3)
        XCTAssertEqual(chapter.startTime, 500.0)
        XCTAssertEqual(chapter.duration, 200.0)
        XCTAssertEqual(chapter.title, "Intro")
        XCTAssertNil(chapter.filePath)
        XCTAssertNil(chapter.fileSize)
        XCTAssertNil(chapter.createdAt)
    }

    // MARK: - AuthResponse Decoding

    func testAuthResponseDecodes() throws {
        let json = """
        {
            "token": "abc123token",
            "user": {
                "id": 1,
                "username": "testuser",
                "is_admin": 0
            },
            "must_change_password": false,
            "mfa_required": true,
            "mfa_token": "mfa-xyz"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.token, "abc123token")
        XCTAssertEqual(response.user.id, 1)
        XCTAssertEqual(response.user.username, "testuser")
        XCTAssertFalse(response.user.isAdminUser)
        XCTAssertEqual(response.mustChangePassword, false)
        XCTAssertEqual(response.mfaRequired, true)
        XCTAssertEqual(response.mfaToken, "mfa-xyz")
    }

    func testAuthResponseDecodesWithoutOptionalFields() throws {
        let json = """
        {
            "token": "token123",
            "user": {
                "id": 5,
                "username": "admin",
                "is_admin": 1
            }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.token, "token123")
        XCTAssertTrue(response.user.isAdminUser)
        XCTAssertNil(response.mustChangePassword)
        XCTAssertNil(response.mfaRequired)
        XCTAssertNil(response.mfaToken)
    }

    // MARK: - User Decoding

    func testUserDecodesFullJSON() throws {
        let json = """
        {
            "id": 1,
            "username": "mondo",
            "email": "mondo@test.com",
            "display_name": "Mondo",
            "is_admin": 1,
            "avatar": "avatar.jpg",
            "must_change_password": false,
            "created_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let user = try decoder.decode(User.self, from: json)

        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.username, "mondo")
        XCTAssertEqual(user.email, "mondo@test.com")
        XCTAssertEqual(user.displayName, "Mondo")
        XCTAssertTrue(user.isAdminUser)
        XCTAssertEqual(user.avatar, "avatar.jpg")
        XCTAssertEqual(user.mustChangePassword, false)
    }

    func testUserIsAdminProperty() throws {
        let adminJSON = """
        {"id": 1, "username": "a", "is_admin": 1}
        """.data(using: .utf8)!

        let nonAdminJSON = """
        {"id": 2, "username": "b", "is_admin": 0}
        """.data(using: .utf8)!

        let admin = try decoder.decode(User.self, from: adminJSON)
        let nonAdmin = try decoder.decode(User.self, from: nonAdminJSON)

        XCTAssertTrue(admin.isAdminUser)
        XCTAssertFalse(nonAdmin.isAdminUser)
    }

    // MARK: - UserStats Decoding

    func testUserStatsDecodesWithDefaults() throws {
        let json = "{}".data(using: .utf8)!

        let stats = try decoder.decode(UserStats.self, from: json)

        XCTAssertEqual(stats.totalListenTime, 0)
        XCTAssertEqual(stats.booksStarted, 0)
        XCTAssertEqual(stats.booksCompleted, 0)
        XCTAssertEqual(stats.currentlyListening, 0)
        XCTAssertTrue(stats.topAuthors.isEmpty)
        XCTAssertTrue(stats.topGenres.isEmpty)
        XCTAssertTrue(stats.recentActivity.isEmpty)
        XCTAssertEqual(stats.activeDaysLast30, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.avgSessionLength, 0)
    }

    func testUserStatsDecodesFullJSON() throws {
        let json = """
        {
            "totalListenTime": 36000,
            "booksStarted": 10,
            "booksCompleted": 5,
            "currentlyListening": 3,
            "topAuthors": [{"author": "Tolkien", "listenTime": 20000, "bookCount": 4}],
            "topGenres": [{"genre": "Fantasy", "listenTime": 25000, "bookCount": 6}],
            "recentActivity": [],
            "activeDaysLast30": 15,
            "currentStreak": 7,
            "avgSessionLength": 45.5
        }
        """.data(using: .utf8)!

        let stats = try decoder.decode(UserStats.self, from: json)

        XCTAssertEqual(stats.totalListenTime, 36000)
        XCTAssertEqual(stats.booksStarted, 10)
        XCTAssertEqual(stats.booksCompleted, 5)
        XCTAssertEqual(stats.currentlyListening, 3)
        XCTAssertEqual(stats.topAuthors.count, 1)
        XCTAssertEqual(stats.topAuthors.first?.author, "Tolkien")
        XCTAssertEqual(stats.topGenres.count, 1)
        XCTAssertEqual(stats.topGenres.first?.genre, "Fantasy")
        XCTAssertEqual(stats.activeDaysLast30, 15)
        XCTAssertEqual(stats.currentStreak, 7)
        XCTAssertEqual(Double(stats.avgSessionLength), 45.5, accuracy: 0.01)
    }

    // MARK: - AudiobooksResponse Decoding

    func testAudiobooksResponseDecodes() throws {
        let json = """
        {
            "audiobooks": [
                {"id": 1, "title": "Book One"},
                {"id": 2, "title": "Book Two"}
            ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(AudiobooksResponse.self, from: json)
        XCTAssertEqual(response.audiobooks.count, 2)
        XCTAssertEqual(response.audiobooks[0].title, "Book One")
        XCTAssertEqual(response.audiobooks[1].title, "Book Two")
    }

    // MARK: - Audiobook with Embedded Progress

    func testAudiobookWithEmbeddedProgress() throws {
        let json = """
        {
            "id": 1,
            "title": "In Progress Book",
            "progress": {
                "id": 5,
                "user_id": 1,
                "audiobook_id": 1,
                "position": 600,
                "completed": 0,
                "current_chapter": 2
            }
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)

        XCTAssertNotNil(book.progress)
        XCTAssertEqual(book.progress?.position, 600)
        XCTAssertEqual(book.progress?.completed, 0)
        XCTAssertEqual(book.progress?.currentChapter, 2)
        XCTAssertFalse(book.progress?.isCompleted ?? true)
    }

    // MARK: - Audiobook with Embedded Chapters

    func testAudiobookWithEmbeddedChapters() throws {
        let json = """
        {
            "id": 1,
            "title": "Book With Chapters",
            "chapters": [
                {"id": 1, "audiobook_id": 1, "chapter_number": 1, "start_time": 0, "duration": 600, "title": "Prologue"},
                {"id": 2, "audiobook_id": 1, "chapter_number": 2, "start_time": 600, "duration": 900, "title": "Chapter 1"}
            ]
        }
        """.data(using: .utf8)!

        let book = try decoder.decode(Audiobook.self, from: json)

        XCTAssertEqual(book.chapters?.count, 2)
        XCTAssertEqual(book.chapters?[0].title, "Prologue")
        XCTAssertEqual(book.chapters?[0].startTime, 0)
        XCTAssertEqual(book.chapters?[1].title, "Chapter 1")
        XCTAssertEqual(book.chapters?[1].startTime, 600)
    }

    // MARK: - FavoriteResponse

    func testFavoriteResponseDecodes() throws {
        let json = """
        {"success": true, "is_favorite": true}
        """.data(using: .utf8)!

        let response = try decoder.decode(FavoriteResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertTrue(response.isFavorite)
    }

    // MARK: - HealthResponse

    func testHealthResponseDecodes() throws {
        let json = """
        {"status": "ok", "message": "Server is running", "version": "1.2.3"}
        """.data(using: .utf8)!

        let response = try decoder.decode(HealthResponse.self, from: json)
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.message, "Server is running")
        XCTAssertEqual(response.version, "1.2.3")
    }

    // MARK: - CollectionForBook

    func testCollectionForBookIsInCollection() throws {
        let inCollectionJSON = """
        {"id": 1, "name": "Favorites", "user_id": 1, "contains_book": 1}
        """.data(using: .utf8)!

        let notInCollectionJSON = """
        {"id": 2, "name": "Read Later", "user_id": 1, "contains_book": 0}
        """.data(using: .utf8)!

        let inCollection = try decoder.decode(CollectionForBook.self, from: inCollectionJSON)
        let notInCollection = try decoder.decode(CollectionForBook.self, from: notInCollectionJSON)

        XCTAssertTrue(inCollection.isInCollection)
        XCTAssertFalse(notInCollection.isInCollection)
    }

    // MARK: - AdminUser

    func testAdminUserProperties() throws {
        let json = """
        {
            "id": 1,
            "username": "admin",
            "is_admin": 1,
            "is_disabled": 0
        }
        """.data(using: .utf8)!

        let user = try decoder.decode(AdminUser.self, from: json)
        XCTAssertTrue(user.isAdminUser)
        XCTAssertFalse(user.isAccountDisabled)
    }

    func testAdminUserDisabled() throws {
        let json = """
        {
            "id": 2,
            "username": "blocked",
            "is_admin": 0,
            "is_disabled": 1
        }
        """.data(using: .utf8)!

        let user = try decoder.decode(AdminUser.self, from: json)
        XCTAssertFalse(user.isAdminUser)
        XCTAssertTrue(user.isAccountDisabled)
    }

    // MARK: - SeriesInfo with string cover_ids

    func testSeriesInfoDecodesStringCoverIds() throws {
        let json = """
        {
            "series": "Lord of the Rings",
            "book_count": 3,
            "cover_ids": ["10", "20", "30"]
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(SeriesInfo.self, from: json)

        XCTAssertEqual(info.series, "Lord of the Rings")
        XCTAssertEqual(info.bookCount, 3)
        XCTAssertEqual(info.coverIds, [10, 20, 30])
    }

    func testSeriesInfoFiltersBadCoverIds() throws {
        let json = """
        {
            "series": "Test",
            "cover_ids": ["1", "abc", "3"]
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(SeriesInfo.self, from: json)
        XCTAssertEqual(info.coverIds, [1, 3])
    }

    // MARK: - AuthorInfo with string cover_ids

    func testAuthorInfoDecodesStringCoverIds() throws {
        let json = """
        {
            "author": "Brandon Sanderson",
            "book_count": 15,
            "cover_ids": ["100", "200"]
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(AuthorInfo.self, from: json)
        XCTAssertEqual(info.author, "Brandon Sanderson")
        XCTAssertEqual(info.bookCount, 15)
        XCTAssertEqual(info.coverIds, [100, 200])
    }

    // MARK: - GenreInfo

    func testGenreInfoDecodes() throws {
        let json = """
        {
            "genre": "Science Fiction",
            "count": 42,
            "cover_ids": [1, 2, 3],
            "color": "#FF5733",
            "icon": "rocket"
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(GenreInfo.self, from: json)
        XCTAssertEqual(info.genre, "Science Fiction")
        XCTAssertEqual(info.id, "Science Fiction")
        XCTAssertEqual(info.count, 42)
        XCTAssertEqual(info.coverIds, [1, 2, 3])
        XCTAssertEqual(info.color, "#FF5733")
        XCTAssertEqual(info.icon, "rocket")
    }

    func testGenreInfoDefaultsEmptyOptionals() throws {
        let json = """
        {"genre": "Thriller"}
        """.data(using: .utf8)!

        let info = try decoder.decode(GenreInfo.self, from: json)
        XCTAssertEqual(info.count, 0)
        XCTAssertTrue(info.coverIds.isEmpty)
        XCTAssertNil(info.color)
        XCTAssertNil(info.icon)
    }
}
