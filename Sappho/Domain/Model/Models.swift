import Foundation

// MARK: - Audiobook
struct Audiobook: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String?
    let author: String?
    let narrator: String?
    let series: String?
    let seriesPosition: Float?
    let seriesIndex: Float?
    let duration: Int?
    let genre: String?
    let normalizedGenre: String?
    let tags: String?
    let publishYear: Int?
    let copyrightYear: Int?
    let publisher: String?
    let isbn: String?
    let asin: String?
    let language: String?
    let rating: Float?
    let userRating: Float?
    let averageRating: Float?
    let abridged: Int?
    let description: String?
    let coverImage: String?
    let fileCount: Int
    let isMultiFile: Int?
    let createdAt: String
    let progress: Progress?
    let chapters: [Chapter]?
    let isFavorite: Bool
    let isQueued: Bool?
    let lastPlayed: String?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, author, narrator, series, duration, genre, tags
        case publisher, isbn, asin, language, rating, description, chapters
        case seriesPosition = "series_position"
        case seriesIndex = "series_index"
        case normalizedGenre = "normalized_genre"
        case publishYear = "published_year"
        case copyrightYear = "copyright_year"
        case userRating = "user_rating"
        case averageRating = "average_rating"
        case abridged
        case coverImage = "cover_image"
        case fileCount = "file_count"
        case isMultiFile = "is_multi_file"
        case createdAt = "created_at"
        case progress
        case isFavorite = "is_favorite"
        case isQueued = "is_queued"
        case lastPlayed = "last_played"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        narrator = try container.decodeIfPresent(String.self, forKey: .narrator)
        series = try container.decodeIfPresent(String.self, forKey: .series)
        seriesPosition = try container.decodeIfPresent(Float.self, forKey: .seriesPosition)
        seriesIndex = try container.decodeIfPresent(Float.self, forKey: .seriesIndex)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        normalizedGenre = try container.decodeIfPresent(String.self, forKey: .normalizedGenre)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        publishYear = try container.decodeIfPresent(Int.self, forKey: .publishYear)
        copyrightYear = try container.decodeIfPresent(Int.self, forKey: .copyrightYear)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        asin = try container.decodeIfPresent(String.self, forKey: .asin)
        language = try container.decodeIfPresent(String.self, forKey: .language)

        // rating can be String or Float from server
        if let ratingFloat = try? container.decodeIfPresent(Float.self, forKey: .rating) {
            rating = ratingFloat
        } else if let ratingString = try? container.decodeIfPresent(String.self, forKey: .rating),
                  let ratingFloat = Float(ratingString) {
            rating = ratingFloat
        } else {
            rating = nil
        }

        userRating = try container.decodeIfPresent(Float.self, forKey: .userRating)
        averageRating = try container.decodeIfPresent(Float.self, forKey: .averageRating)
        abridged = try container.decodeIfPresent(Int.self, forKey: .abridged)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImage = try container.decodeIfPresent(String.self, forKey: .coverImage)
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount) ?? 1
        isMultiFile = try container.decodeIfPresent(Int.self, forKey: .isMultiFile)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        progress = try container.decodeIfPresent(Progress.self, forKey: .progress)
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters)

        // is_favorite can be Bool or Int (0/1) from server
        if let favBool = try? container.decodeIfPresent(Bool.self, forKey: .isFavorite) {
            isFavorite = favBool ?? false
        } else if let favInt = try? container.decodeIfPresent(Int.self, forKey: .isFavorite) {
            isFavorite = favInt == 1
        } else {
            isFavorite = false
        }

        // is_queued can be Bool or Int (0/1) from server
        if let queuedBool = try? container.decodeIfPresent(Bool.self, forKey: .isQueued) {
            isQueued = queuedBool
        } else if let queuedInt = try? container.decodeIfPresent(Int.self, forKey: .isQueued) {
            isQueued = queuedInt == 1
        } else {
            isQueued = nil
        }

        lastPlayed = try container.decodeIfPresent(String.self, forKey: .lastPlayed)
    }

    // Memberwise initializer for previews and testing
    init(
        id: Int,
        title: String,
        subtitle: String? = nil,
        author: String? = nil,
        narrator: String? = nil,
        series: String? = nil,
        seriesPosition: Float? = nil,
        seriesIndex: Float? = nil,
        duration: Int? = nil,
        genre: String? = nil,
        normalizedGenre: String? = nil,
        tags: String? = nil,
        publishYear: Int? = nil,
        copyrightYear: Int? = nil,
        publisher: String? = nil,
        isbn: String? = nil,
        asin: String? = nil,
        language: String? = nil,
        rating: Float? = nil,
        userRating: Float? = nil,
        averageRating: Float? = nil,
        abridged: Int? = nil,
        description: String? = nil,
        coverImage: String? = nil,
        fileCount: Int = 1,
        isMultiFile: Int? = nil,
        createdAt: String = "",
        progress: Progress? = nil,
        chapters: [Chapter]? = nil,
        isFavorite: Bool = false,
        isQueued: Bool? = nil,
        lastPlayed: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.narrator = narrator
        self.series = series
        self.seriesPosition = seriesPosition
        self.seriesIndex = seriesIndex
        self.duration = duration
        self.genre = genre
        self.normalizedGenre = normalizedGenre
        self.tags = tags
        self.publishYear = publishYear
        self.copyrightYear = copyrightYear
        self.publisher = publisher
        self.isbn = isbn
        self.asin = asin
        self.language = language
        self.rating = rating
        self.userRating = userRating
        self.averageRating = averageRating
        self.abridged = abridged
        self.description = description
        self.coverImage = coverImage
        self.fileCount = fileCount
        self.isMultiFile = isMultiFile
        self.createdAt = createdAt
        self.progress = progress
        self.chapters = chapters
        self.isFavorite = isFavorite
        self.isQueued = isQueued
        self.lastPlayed = lastPlayed
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Audiobook, rhs: Audiobook) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Progress
struct Progress: Codable {
    let id: Int?
    let userId: Int?
    let audiobookId: Int?
    let position: Int
    let completed: Int
    let lastListened: String?
    let updatedAt: String?
    let currentChapter: Int?

    enum CodingKeys: String, CodingKey {
        case id, position, completed
        case userId = "user_id"
        case audiobookId = "audiobook_id"
        case lastListened = "last_listened"
        case updatedAt = "updated_at"
        case currentChapter = "current_chapter"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        audiobookId = try container.decodeIfPresent(Int.self, forKey: .audiobookId)
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        completed = try container.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        lastListened = try container.decodeIfPresent(String.self, forKey: .lastListened)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        currentChapter = try container.decodeIfPresent(Int.self, forKey: .currentChapter)
    }

    var isCompleted: Bool {
        completed == 1
    }

    var progressPercentage: Double {
        guard let audiobookId = audiobookId else { return 0 }
        // This would need duration from the audiobook to calculate properly
        return 0
    }
}

// MARK: - Chapter
struct Chapter: Codable, Identifiable {
    let id: Int
    let audiobookId: Int
    let chapterNumber: Int
    let filePath: String?
    let startTime: Double
    let duration: Int?
    let fileSize: Int?
    let title: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, duration
        case audiobookId = "audiobook_id"
        case chapterNumber = "chapter_number"
        case filePath = "file_path"
        case startTime = "start_time"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        audiobookId = try container.decode(Int.self, forKey: .audiobookId)
        chapterNumber = try container.decodeIfPresent(Int.self, forKey: .chapterNumber) ?? 0
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime) ?? 0
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

// MARK: - User
struct User: Codable, Identifiable {
    let id: Int
    let username: String?
    let email: String?
    let displayName: String?
    let isAdmin: Int
    let avatar: String?
    let mustChangePassword: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, email, avatar
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case mustChangePassword = "must_change_password"
        case createdAt = "created_at"
    }

    var isAdminUser: Bool {
        isAdmin == 1
    }
}

// MARK: - Auth Response
struct AuthResponse: Codable {
    let token: String
    let user: LoginUser
    let mustChangePassword: Bool?
    let mfaRequired: Bool?
    let mfaToken: String?

    enum CodingKeys: String, CodingKey {
        case token, user
        case mustChangePassword = "must_change_password"
        case mfaRequired = "mfa_required"
        case mfaToken = "mfa_token"
    }
}

// MARK: - Login User (minimal user info returned from login)
struct LoginUser: Codable {
    let id: Int
    let username: String
    let isAdmin: Int

    enum CodingKeys: String, CodingKey {
        case id, username
        case isAdmin = "is_admin"
    }

    var isAdminUser: Bool {
        isAdmin == 1
    }
}

// MARK: - Audiobooks Response
struct AudiobooksResponse: Codable {
    let audiobooks: [Audiobook]
}

// MARK: - User Stats
struct UserStats: Codable {
    let totalListenTime: Int
    let booksStarted: Int
    let booksCompleted: Int
    let currentlyListening: Int
    let topAuthors: [AuthorListenStat]
    let topGenres: [GenreListenStat]
    let recentActivity: [RecentActivityItem]
    let activeDaysLast30: Int
    let currentStreak: Int
    let avgSessionLength: Float

    enum CodingKeys: String, CodingKey {
        case totalListenTime, booksStarted, booksCompleted, currentlyListening
        case topAuthors, topGenres, recentActivity
        case activeDaysLast30, currentStreak, avgSessionLength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalListenTime = try container.decodeIfPresent(Int.self, forKey: .totalListenTime) ?? 0
        booksStarted = try container.decodeIfPresent(Int.self, forKey: .booksStarted) ?? 0
        booksCompleted = try container.decodeIfPresent(Int.self, forKey: .booksCompleted) ?? 0
        currentlyListening = try container.decodeIfPresent(Int.self, forKey: .currentlyListening) ?? 0
        topAuthors = try container.decodeIfPresent([AuthorListenStat].self, forKey: .topAuthors) ?? []
        topGenres = try container.decodeIfPresent([GenreListenStat].self, forKey: .topGenres) ?? []
        recentActivity = try container.decodeIfPresent([RecentActivityItem].self, forKey: .recentActivity) ?? []
        activeDaysLast30 = try container.decodeIfPresent(Int.self, forKey: .activeDaysLast30) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        avgSessionLength = try container.decodeIfPresent(Float.self, forKey: .avgSessionLength) ?? 0
    }
}

struct AuthorListenStat: Codable {
    let author: String
    let listenTime: Int
    let bookCount: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        listenTime = try container.decodeIfPresent(Int.self, forKey: .listenTime) ?? 0
        bookCount = try container.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
    }
}

struct GenreListenStat: Codable {
    let genre: String
    let listenTime: Int
    let bookCount: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genre = try container.decodeIfPresent(String.self, forKey: .genre) ?? ""
        listenTime = try container.decodeIfPresent(Int.self, forKey: .listenTime) ?? 0
        bookCount = try container.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
    }
}

struct RecentActivityItem: Codable, Identifiable {
    let id: Int
    let title: String
    let author: String?
    let coverImage: String?
    let position: Int
    let duration: Int?
    let completed: Int
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, position, duration, completed
        case coverImage = "cover_image"
        case updatedAt = "updated_at"
    }
}

// MARK: - Genre Info
struct GenreInfo: Codable, Identifiable {
    var id: String { genre }
    let genre: String
    let count: Int
    let coverIds: [Int]
    let color: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case genre, count, color, icon
        case coverIds = "cover_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genre = try container.decode(String.self, forKey: .genre)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        coverIds = try container.decodeIfPresent([Int].self, forKey: .coverIds) ?? []
        color = try container.decodeIfPresent(String.self, forKey: .color)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }
}

// MARK: - Series Info
struct SeriesInfo: Codable, Identifiable {
    var id: String { series }
    let series: String
    let bookCount: Int
    let coverIds: [Int]
    let completedCount: Int?
    let averageRating: Float?
    let ratingCount: Int?

    enum CodingKeys: String, CodingKey {
        case series
        case bookCount = "book_count"
        case coverIds = "cover_ids"
        case completedCount = "completed_count"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        series = try container.decode(String.self, forKey: .series)
        bookCount = try container.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
        // Server sends cover_ids as strings (from split), convert to Int
        let stringIds = try container.decodeIfPresent([String].self, forKey: .coverIds) ?? []
        coverIds = stringIds.compactMap { Int($0) }
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount)
        averageRating = try container.decodeIfPresent(Float.self, forKey: .averageRating)
        ratingCount = try container.decodeIfPresent(Int.self, forKey: .ratingCount)
    }
}

// MARK: - Author Info
struct AuthorInfo: Codable, Identifiable {
    var id: String { author }
    let author: String
    let bookCount: Int
    let coverIds: [Int]
    let completedCount: Int?

    enum CodingKeys: String, CodingKey {
        case author
        case bookCount = "book_count"
        case coverIds = "cover_ids"
        case completedCount = "completed_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(String.self, forKey: .author)
        bookCount = try container.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
        // Server sends cover_ids as strings (from split), convert to Int
        let stringIds = try container.decodeIfPresent([String].self, forKey: .coverIds) ?? []
        coverIds = stringIds.compactMap { Int($0) }
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount)
    }
}

// MARK: - Collection
struct Collection: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let userId: Int
    let bookCount: Int?
    let firstCover: String?
    let bookIds: [Int]?
    let isPublic: Int?
    let isOwner: Int?
    let creatorUsername: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case userId = "user_id"
        case bookCount = "book_count"
        case firstCover = "first_cover"
        case bookIds = "book_ids"
        case isPublic = "is_public"
        case isOwner = "is_owner"
        case creatorUsername = "creator_username"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Favorite Response
struct FavoriteResponse: Codable {
    let success: Bool
    let isFavorite: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case isFavorite = "is_favorite"
    }
}

// MARK: - Series Recap Response
struct SeriesRecapResponse: Codable {
    let recap: String
    let cached: Bool
    let cachedAt: String?
    let booksIncluded: [RecapBookInfo]

    enum CodingKeys: String, CodingKey {
        case recap, cached
        case cachedAt = "cached_at"
        case booksIncluded = "books_included"
    }
}

struct RecapBookInfo: Codable, Identifiable {
    let id: Int
    let title: String
    let position: Float?
}

// MARK: - Rating
struct UserRating: Codable {
    let id: Int
    let userId: Int
    let audiobookId: Int
    let rating: Int?
    let review: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, rating, review
        case userId = "user_id"
        case audiobookId = "audiobook_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AverageRating: Codable {
    let average: Float?
    let count: Int
}

// MARK: - Health Response
struct HealthResponse: Codable {
    let status: String
    let message: String
    let version: String?
}

// MARK: - Upload Response
struct UploadResponse: Codable {
    let message: String?
    let audiobook: Audiobook?
}

// MARK: - Collection Detail (single collection with books)
struct CollectionDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let userId: Int
    let isPublic: Int?
    let isOwner: Int?
    let creatorUsername: String?
    let createdAt: String?
    let updatedAt: String?
    let books: [Audiobook]

    enum CodingKeys: String, CodingKey {
        case id, name, description, books
        case userId = "user_id"
        case isPublic = "is_public"
        case isOwner = "is_owner"
        case creatorUsername = "creator_username"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Collection for Book (checking which collections contain a book)
struct CollectionForBook: Codable, Identifiable {
    let id: Int
    let name: String
    let isPublic: Int?
    let userId: Int
    let creatorUsername: String?
    let containsBook: Int
    let isOwner: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case isPublic = "is_public"
        case userId = "user_id"
        case creatorUsername = "creator_username"
        case containsBook = "contains_book"
        case isOwner = "is_owner"
    }

    var isInCollection: Bool {
        containsBook == 1
    }
}

// MARK: - Admin User
struct AdminUser: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String?
    let displayName: String?
    let isAdmin: Int
    let createdAt: String?
    let lastLogin: String?
    let isDisabled: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case lastLogin = "last_login"
        case isDisabled = "is_disabled"
    }

    var isAdminUser: Bool {
        isAdmin == 1
    }

    var isAccountDisabled: Bool {
        isDisabled == 1
    }
}

// MARK: - Scan Response
struct ScanResponse: Codable {
    let message: String
    let newBooks: Int?
    let totalBooks: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case newBooks = "new_books"
        case totalBooks = "total_books"
    }
}
