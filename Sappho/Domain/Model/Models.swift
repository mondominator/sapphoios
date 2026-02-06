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
    let duration: Int?
    let genre: String?
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

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, author, narrator, series, duration, genre, tags
        case publisher, isbn, asin, language, rating, description, chapters
        case seriesPosition = "series_position"
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
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        publishYear = try container.decodeIfPresent(Int.self, forKey: .publishYear)
        copyrightYear = try container.decodeIfPresent(Int.self, forKey: .copyrightYear)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        asin = try container.decodeIfPresent(String.self, forKey: .asin)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        rating = try container.decodeIfPresent(Float.self, forKey: .rating)
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
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
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
    let currentChapter: Int?

    enum CodingKeys: String, CodingKey {
        case id, position, completed
        case userId = "user_id"
        case audiobookId = "audiobook_id"
        case lastListened = "last_listened"
        case currentChapter = "current_chapter"
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
    let fileId: Int
    let startTime: Double
    let endTime: Double?
    let title: String?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, duration
        case audiobookId = "audiobook_id"
        case fileId = "file_id"
        case startTime = "start_time"
        case endTime = "end_time"
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
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, email, avatar
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case createdAt = "created_at"
    }

    var isAdminUser: Bool {
        isAdmin == 1
    }
}

// MARK: - Auth Response
struct AuthResponse: Codable {
    let token: String
    let user: User
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

    enum CodingKeys: String, CodingKey {
        case genre, count
        case coverIds = "cover_ids"
    }
}

// MARK: - Series Info
struct SeriesInfo: Codable, Identifiable {
    var id: String { series }
    let series: String
    let bookCount: Int

    enum CodingKeys: String, CodingKey {
        case series
        case bookCount = "book_count"
    }
}

// MARK: - Author Info
struct AuthorInfo: Codable, Identifiable {
    var id: String { author }
    let author: String
    let bookCount: Int

    enum CodingKeys: String, CodingKey {
        case author
        case bookCount = "book_count"
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
