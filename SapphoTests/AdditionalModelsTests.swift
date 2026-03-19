import XCTest
@testable import Sappho

final class AdditionalModelsTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Collection Decoding

    func testCollectionDecodesFullJSON() throws {
        let json = """
        {
            "id": 1,
            "name": "Favorites",
            "description": "My favorite books",
            "user_id": 10,
            "book_count": 5,
            "first_cover": "cover.jpg",
            "book_ids": [1, 2, 3],
            "is_public": 1,
            "is_owner": 1,
            "creator_username": "mondo",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let collection = try decoder.decode(Collection.self, from: json)

        XCTAssertEqual(collection.id, 1)
        XCTAssertEqual(collection.name, "Favorites")
        XCTAssertEqual(collection.description, "My favorite books")
        XCTAssertEqual(collection.userId, 10)
        XCTAssertEqual(collection.bookCount, 5)
        XCTAssertEqual(collection.firstCover, "cover.jpg")
        XCTAssertEqual(collection.bookIds, [1, 2, 3])
        XCTAssertEqual(collection.isPublic, 1)
        XCTAssertEqual(collection.isOwner, 1)
        XCTAssertEqual(collection.creatorUsername, "mondo")
    }

    func testCollectionDecodesMinimalJSON() throws {
        let json = """
        {
            "id": 2,
            "name": "Test",
            "user_id": 1
        }
        """.data(using: .utf8)!

        let collection = try decoder.decode(Collection.self, from: json)

        XCTAssertEqual(collection.id, 2)
        XCTAssertEqual(collection.name, "Test")
        XCTAssertEqual(collection.userId, 1)
        XCTAssertNil(collection.description)
        XCTAssertNil(collection.bookCount)
        XCTAssertNil(collection.firstCover)
        XCTAssertNil(collection.bookIds)
        XCTAssertNil(collection.isPublic)
    }

    // MARK: - CollectionDetail Decoding

    func testCollectionDetailDecodes() throws {
        let json = """
        {
            "id": 1,
            "name": "Sci-Fi Collection",
            "description": "Best sci-fi books",
            "user_id": 5,
            "is_public": 1,
            "is_owner": 1,
            "creator_username": "admin",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-01T00:00:00Z",
            "books": [
                {"id": 1, "title": "Dune"},
                {"id": 2, "title": "Foundation"}
            ]
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(CollectionDetail.self, from: json)

        XCTAssertEqual(detail.id, 1)
        XCTAssertEqual(detail.name, "Sci-Fi Collection")
        XCTAssertEqual(detail.books.count, 2)
        XCTAssertEqual(detail.books[0].title, "Dune")
        XCTAssertEqual(detail.books[1].title, "Foundation")
        XCTAssertEqual(detail.isOwner, 1)
    }

    func testCollectionDetailWithEmptyBooks() throws {
        let json = """
        {
            "id": 3,
            "name": "Empty Collection",
            "user_id": 1,
            "books": []
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(CollectionDetail.self, from: json)
        XCTAssertEqual(detail.id, 3)
        XCTAssertTrue(detail.books.isEmpty)
    }

    // MARK: - NotificationItem Decoding

    func testNotificationItemDecodes() throws {
        let json = """
        {
            "id": 100,
            "type": "new_book",
            "title": "New Book Available",
            "message": "A new book was added to the library",
            "metadata": "{\\"book_id\\": 42}",
            "created_at": "2024-06-01T12:00:00Z",
            "is_read": 0
        }
        """.data(using: .utf8)!

        let notification = try decoder.decode(NotificationItem.self, from: json)

        XCTAssertEqual(notification.id, 100)
        XCTAssertEqual(notification.type, "new_book")
        XCTAssertEqual(notification.title, "New Book Available")
        XCTAssertEqual(notification.message, "A new book was added to the library")
        XCTAssertTrue(notification.isUnread)
        XCTAssertEqual(notification.isRead, 0)
    }

    func testNotificationItemIsReadWhenRead() throws {
        let json = """
        {
            "id": 101,
            "type": "system",
            "title": "Update",
            "message": "System update",
            "created_at": "2024-06-01T12:00:00Z",
            "is_read": 1
        }
        """.data(using: .utf8)!

        let notification = try decoder.decode(NotificationItem.self, from: json)
        XCTAssertFalse(notification.isUnread)
        XCTAssertEqual(notification.isRead, 1)
    }

    func testNotificationMetadataDict() throws {
        let json = """
        {
            "id": 1,
            "type": "test",
            "title": "Test",
            "message": "Test",
            "metadata": "{\\"book_id\\": 42, \\"action\\": \\"added\\"}",
            "created_at": "2024-01-01T00:00:00Z",
            "is_read": 0
        }
        """.data(using: .utf8)!

        let notification = try decoder.decode(NotificationItem.self, from: json)
        let dict = notification.metadataDict

        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["book_id"] as? Int, 42)
        XCTAssertEqual(dict?["action"] as? String, "added")
    }

    func testNotificationMetadataDictNilForNilMetadata() throws {
        let json = """
        {
            "id": 1,
            "type": "test",
            "title": "Test",
            "message": "Test",
            "created_at": "2024-01-01T00:00:00Z",
            "is_read": 0
        }
        """.data(using: .utf8)!

        let notification = try decoder.decode(NotificationItem.self, from: json)
        XCTAssertNil(notification.metadataDict)
    }

    // MARK: - UnreadCount

    func testUnreadCountDecodes() throws {
        let json = """
        {"count": 5}
        """.data(using: .utf8)!

        let unread = try decoder.decode(UnreadCount.self, from: json)
        XCTAssertEqual(unread.count, 5)
    }

    // MARK: - UserRating Decoding

    func testUserRatingDecodes() throws {
        let json = """
        {
            "id": 1,
            "user_id": 10,
            "audiobook_id": 42,
            "rating": 5,
            "review": "Excellent book!",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let rating = try decoder.decode(UserRating.self, from: json)

        XCTAssertEqual(rating.id, 1)
        XCTAssertEqual(rating.userId, 10)
        XCTAssertEqual(rating.audiobookId, 42)
        XCTAssertEqual(rating.rating, 5)
        XCTAssertEqual(rating.review, "Excellent book!")
    }

    func testUserRatingWithNullRating() throws {
        let json = """
        {
            "id": 2,
            "user_id": 10,
            "audiobook_id": 42,
            "rating": null,
            "review": null
        }
        """.data(using: .utf8)!

        let rating = try decoder.decode(UserRating.self, from: json)
        XCTAssertNil(rating.rating)
        XCTAssertNil(rating.review)
    }

    // MARK: - AverageRating

    func testAverageRatingDecodes() throws {
        let json = """
        {"average": 4.2, "count": 15}
        """.data(using: .utf8)!

        let avg = try decoder.decode(AverageRating.self, from: json)
        XCTAssertEqual(Double(avg.average ?? 0), 4.2, accuracy: 0.01)
        XCTAssertEqual(avg.count, 15)
    }

    func testAverageRatingWithNullAverage() throws {
        let json = """
        {"average": null, "count": 0}
        """.data(using: .utf8)!

        let avg = try decoder.decode(AverageRating.self, from: json)
        XCTAssertNil(avg.average)
        XCTAssertEqual(avg.count, 0)
    }

    // MARK: - ReviewItem

    func testReviewItemDecodes() throws {
        let json = """
        {
            "id": 1,
            "user_id": 5,
            "audiobook_id": 42,
            "rating": 4,
            "review": "Great listen!",
            "username": "reader1",
            "display_name": "Avid Reader",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let review = try decoder.decode(ReviewItem.self, from: json)

        XCTAssertEqual(review.id, 1)
        XCTAssertEqual(review.userId, 5)
        XCTAssertEqual(review.audiobookId, 42)
        XCTAssertEqual(review.rating, 4)
        XCTAssertEqual(review.review, "Great listen!")
        XCTAssertEqual(review.username, "reader1")
        XCTAssertEqual(review.displayName, "Avid Reader")
    }

    // MARK: - ScanResponse

    func testScanResponseDecodes() throws {
        let json = """
        {
            "message": "Scan complete",
            "new_books": 3,
            "total_books": 150
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ScanResponse.self, from: json)
        XCTAssertEqual(response.message, "Scan complete")
        XCTAssertEqual(response.newBooks, 3)
        XCTAssertEqual(response.totalBooks, 150)
    }

    func testScanResponseMinimal() throws {
        let json = """
        {"message": "Scan started"}
        """.data(using: .utf8)!

        let response = try decoder.decode(ScanResponse.self, from: json)
        XCTAssertEqual(response.message, "Scan started")
        XCTAssertNil(response.newBooks)
        XCTAssertNil(response.totalBooks)
    }

    // MARK: - UploadResponse

    func testUploadResponseDecodes() throws {
        let json = """
        {
            "message": "Upload successful",
            "audiobook": {
                "id": 999,
                "title": "Uploaded Book"
            }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(UploadResponse.self, from: json)
        XCTAssertEqual(response.message, "Upload successful")
        XCTAssertEqual(response.audiobook?.id, 999)
        XCTAssertEqual(response.audiobook?.title, "Uploaded Book")
    }

    func testUploadResponseWithoutAudiobook() throws {
        let json = """
        {"message": "Processing..."}
        """.data(using: .utf8)!

        let response = try decoder.decode(UploadResponse.self, from: json)
        XCTAssertEqual(response.message, "Processing...")
        XCTAssertNil(response.audiobook)
    }

    // MARK: - SeriesRecapResponse

    func testSeriesRecapResponseDecodes() throws {
        let json = """
        {
            "recap": "In the first book, the hero embarks on a journey...",
            "cached": true,
            "cached_at": "2024-06-01T00:00:00Z",
            "books_included": [
                {"id": 1, "title": "Book One", "position": 1.0},
                {"id": 2, "title": "Book Two", "position": 2.0}
            ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(SeriesRecapResponse.self, from: json)

        XCTAssertEqual(response.recap, "In the first book, the hero embarks on a journey...")
        XCTAssertTrue(response.cached)
        XCTAssertEqual(response.cachedAt, "2024-06-01T00:00:00Z")
        XCTAssertEqual(response.booksIncluded.count, 2)
        XCTAssertEqual(response.booksIncluded[0].title, "Book One")
        XCTAssertEqual(response.booksIncluded[0].position, 1.0)
    }

    func testSeriesRecapResponseNotCached() throws {
        let json = """
        {
            "recap": "Fresh recap text",
            "cached": false,
            "books_included": []
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(SeriesRecapResponse.self, from: json)
        XCTAssertFalse(response.cached)
        XCTAssertNil(response.cachedAt)
        XCTAssertTrue(response.booksIncluded.isEmpty)
    }

    // MARK: - RecentActivityItem

    func testRecentActivityItemDecodes() throws {
        let json = """
        {
            "id": 42,
            "title": "Currently Reading",
            "author": "Test Author",
            "cover_image": "cover.jpg",
            "position": 1500,
            "duration": 36000,
            "completed": 0,
            "updated_at": "2024-06-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(RecentActivityItem.self, from: json)

        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.title, "Currently Reading")
        XCTAssertEqual(item.author, "Test Author")
        XCTAssertEqual(item.coverImage, "cover.jpg")
        XCTAssertEqual(item.position, 1500)
        XCTAssertEqual(item.duration, 36000)
        XCTAssertEqual(item.completed, 0)
    }

    // MARK: - AuthorListenStat

    func testAuthorListenStatDecodes() throws {
        let json = """
        {"author": "Brandon Sanderson", "listenTime": 50000, "bookCount": 8}
        """.data(using: .utf8)!

        let stat = try decoder.decode(AuthorListenStat.self, from: json)
        XCTAssertEqual(stat.author, "Brandon Sanderson")
        XCTAssertEqual(stat.listenTime, 50000)
        XCTAssertEqual(stat.bookCount, 8)
    }

    func testAuthorListenStatDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let stat = try decoder.decode(AuthorListenStat.self, from: json)

        XCTAssertEqual(stat.author, "")
        XCTAssertEqual(stat.listenTime, 0)
        XCTAssertEqual(stat.bookCount, 0)
    }

    // MARK: - GenreListenStat

    func testGenreListenStatDecodes() throws {
        let json = """
        {"genre": "Fantasy", "listenTime": 80000, "bookCount": 12}
        """.data(using: .utf8)!

        let stat = try decoder.decode(GenreListenStat.self, from: json)
        XCTAssertEqual(stat.genre, "Fantasy")
        XCTAssertEqual(stat.listenTime, 80000)
        XCTAssertEqual(stat.bookCount, 12)
    }

    func testGenreListenStatDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let stat = try decoder.decode(GenreListenStat.self, from: json)

        XCTAssertEqual(stat.genre, "")
        XCTAssertEqual(stat.listenTime, 0)
        XCTAssertEqual(stat.bookCount, 0)
    }

    // MARK: - LoginUser

    func testLoginUserIsAdminUser() throws {
        let adminJSON = """
        {"id": 1, "username": "admin", "is_admin": 1}
        """.data(using: .utf8)!

        let nonAdminJSON = """
        {"id": 2, "username": "user", "is_admin": 0}
        """.data(using: .utf8)!

        let admin = try decoder.decode(LoginUser.self, from: adminJSON)
        let nonAdmin = try decoder.decode(LoginUser.self, from: nonAdminJSON)

        XCTAssertTrue(admin.isAdminUser)
        XCTAssertFalse(nonAdmin.isAdminUser)
    }

    // MARK: - RecapBookInfo

    func testRecapBookInfoDecodes() throws {
        let json = """
        {"id": 10, "title": "Book Title", "position": 3.5}
        """.data(using: .utf8)!

        let info = try decoder.decode(RecapBookInfo.self, from: json)
        XCTAssertEqual(info.id, 10)
        XCTAssertEqual(info.title, "Book Title")
        XCTAssertEqual(info.position, 3.5)
    }

    func testRecapBookInfoWithoutPosition() throws {
        let json = """
        {"id": 10, "title": "Book Title"}
        """.data(using: .utf8)!

        let info = try decoder.decode(RecapBookInfo.self, from: json)
        XCTAssertNil(info.position)
    }

    // MARK: - SeriesInfo Additional

    func testSeriesInfoDecodesWithOptionalFields() throws {
        let json = """
        {
            "series": "Mistborn",
            "book_count": 6,
            "cover_ids": ["10", "20"],
            "completed_count": 3,
            "average_rating": 4.7,
            "rating_count": 100
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(SeriesInfo.self, from: json)
        XCTAssertEqual(info.series, "Mistborn")
        XCTAssertEqual(info.completedCount, 3)
        XCTAssertEqual(Double(info.averageRating ?? 0), 4.7, accuracy: 0.01)
        XCTAssertEqual(info.ratingCount, 100)
    }

    // MARK: - AuthorInfo Additional

    func testAuthorInfoDecodesWithCompletedCount() throws {
        let json = """
        {
            "author": "Terry Pratchett",
            "book_count": 41,
            "cover_ids": ["5", "10", "15"],
            "completed_count": 20
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(AuthorInfo.self, from: json)
        XCTAssertEqual(info.author, "Terry Pratchett")
        XCTAssertEqual(info.bookCount, 41)
        XCTAssertEqual(info.coverIds, [5, 10, 15])
        XCTAssertEqual(info.completedCount, 20)
    }

    // MARK: - Progress Computed Properties

    func testProgressIsCompletedFalseForZero() {
        let progress = Progress(position: 500, completed: 0)
        XCTAssertFalse(progress.isCompleted)
    }

    func testProgressIsCompletedTrueForOne() {
        let progress = Progress(position: 0, completed: 1)
        XCTAssertTrue(progress.isCompleted)
    }
}
