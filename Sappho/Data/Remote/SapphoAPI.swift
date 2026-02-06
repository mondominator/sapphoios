import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return message ?? "HTTP error \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@Observable
class SapphoAPI {
    private let authRepository: AuthRepository
    private let session: URLSession
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, session: URLSession = .shared) {
        self.authRepository = authRepository
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Base Request Methods

    private func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems?.filter { $0.value != nil }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authRepository.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func requestVoid(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authRepository.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Authentication

    func login(serverURL: URL, username: String, password: String) async throws -> AuthResponse {
        var urlComponents = URLComponents(url: serverURL.appendingPathComponent("api/auth/login"), resolvingAgainstBaseURL: true)

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(credentials)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(AuthResponse.self, from: data)
    }

    // MARK: - Audiobooks

    func getAudiobooks(search: String? = nil, status: String? = nil, sort: String? = nil, limit: Int? = nil) async throws -> [Audiobook] {
        var queryItems: [URLQueryItem] = []
        if let search { queryItems.append(URLQueryItem(name: "search", value: search)) }
        if let status { queryItems.append(URLQueryItem(name: "status", value: status)) }
        if let sort { queryItems.append(URLQueryItem(name: "sort", value: sort)) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }

        let response: AudiobooksResponse = try await request("api/audiobooks", queryItems: queryItems.isEmpty ? nil : queryItems)
        return response.audiobooks
    }

    func getAudiobook(id: Int) async throws -> Audiobook {
        try await request("api/audiobooks/\(id)")
    }

    func getRecentlyAdded(limit: Int = 10) async throws -> [Audiobook] {
        try await request("api/audiobooks/meta/recent", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getInProgress(limit: Int = 10) async throws -> [Audiobook] {
        try await request("api/audiobooks/meta/in-progress", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getFinished(limit: Int = 10) async throws -> [Audiobook] {
        try await request("api/audiobooks/meta/finished", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getUpNext(limit: Int = 10) async throws -> [Audiobook] {
        try await request("api/audiobooks/meta/up-next", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getGenres() async throws -> [GenreInfo] {
        try await request("api/audiobooks/meta/genres")
    }

    // MARK: - Progress

    func getProgress(audiobookId: Int) async throws -> Progress {
        try await request("api/audiobooks/\(audiobookId)/progress")
    }

    func updateProgress(audiobookId: Int, position: Int, completed: Int = 0, state: String = "playing") async throws {
        let body = ProgressUpdateRequest(position: position, completed: completed, state: state)
        try await requestVoid("api/audiobooks/\(audiobookId)/progress", method: "POST", body: body)
    }

    func clearProgress(audiobookId: Int) async throws {
        try await requestVoid("api/audiobooks/\(audiobookId)/progress", method: "DELETE")
    }

    // MARK: - Chapters

    func getChapters(audiobookId: Int) async throws -> [Chapter] {
        try await request("api/audiobooks/\(audiobookId)/chapters")
    }

    // MARK: - Favorites

    func getFavorites() async throws -> [Audiobook] {
        try await request("api/audiobooks/favorites")
    }

    func toggleFavorite(audiobookId: Int) async throws -> FavoriteResponse {
        try await request("api/audiobooks/\(audiobookId)/favorite/toggle", method: "POST")
    }

    // MARK: - Collections

    func getCollections() async throws -> [Collection] {
        try await request("api/collections")
    }

    // MARK: - Profile

    func getProfile() async throws -> User {
        try await request("api/profile")
    }

    func getProfileStats() async throws -> UserStats {
        try await request("api/profile/stats")
    }

    func updateProfile(displayName: String?, email: String?) async throws -> User {
        let body = ProfileUpdateRequest(displayName: displayName, email: email)
        return try await request("api/profile", method: "PUT", body: body)
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        let body = PasswordUpdateRequest(currentPassword: currentPassword, newPassword: newPassword)
        try await requestVoid("api/profile/password", method: "PUT", body: body)
    }

    // MARK: - Ratings

    func getUserRating(audiobookId: Int) async throws -> UserRating? {
        try await request("api/ratings/audiobook/\(audiobookId)")
    }

    func getAverageRating(audiobookId: Int) async throws -> AverageRating {
        try await request("api/ratings/audiobook/\(audiobookId)/average")
    }

    func setRating(audiobookId: Int, rating: Int?, review: String? = nil) async throws -> UserRating {
        let body = RatingRequest(rating: rating, review: review)
        return try await request("api/ratings/audiobook/\(audiobookId)", method: "POST", body: body)
    }

    // MARK: - Series Recap

    func getSeriesRecap(seriesName: String) async throws -> SeriesRecapResponse {
        let encoded = seriesName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? seriesName
        return try await request("api/series/\(encoded)/recap")
    }

    // MARK: - Health

    func getHealth() async throws -> HealthResponse {
        try await request("api/health")
    }

    // MARK: - URL Builders

    func coverURL(for audiobookId: Int) -> URL? {
        guard let baseURL = authRepository.serverURL, let token = authRepository.token else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/cover"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    func streamURL(for audiobookId: Int) -> URL? {
        guard let baseURL = authRepository.serverURL, let token = authRepository.token else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/stream"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    func avatarURL() -> URL? {
        guard let baseURL = authRepository.serverURL, let token = authRepository.token else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/profile/avatar"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }
}

// MARK: - Request/Response Types

private struct ErrorResponse: Codable {
    let message: String?
    let error: String?
}

private struct LoginRequest: Codable {
    let username: String
    let password: String
}

private struct ProgressUpdateRequest: Codable {
    let position: Int
    let completed: Int
    let state: String
}

private struct ProfileUpdateRequest: Codable {
    let displayName: String?
    let email: String?
}

private struct PasswordUpdateRequest: Codable {
    let currentPassword: String
    let newPassword: String
}

private struct RatingRequest: Codable {
    let rating: Int?
    let review: String?
}
