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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired. Please log in again.")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            if let json = String(data: data, encoding: .utf8) {
                print("Decoding error for \(T.self):")
                print("Response: \(json.prefix(500))")
                print("Error: \(error)")
            }
            #endif
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired. Please log in again.")
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

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
        // Returns array directly, not wrapped in { audiobooks: [...] }
        try await request("api/audiobooks/meta/recent", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getInProgress(limit: Int = 10) async throws -> [Audiobook] {
        // Returns array directly, not wrapped in { audiobooks: [...] }
        try await request("api/audiobooks/meta/in-progress", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getFinished(limit: Int = 10) async throws -> [Audiobook] {
        // Returns array directly, not wrapped in { audiobooks: [...] }
        try await request("api/audiobooks/meta/finished", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getUpNext(limit: Int = 10) async throws -> [Audiobook] {
        // Returns array directly, not wrapped in { audiobooks: [...] }
        try await request("api/audiobooks/meta/up-next", queryItems: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func getGenres() async throws -> [GenreInfo] {
        try await request("api/audiobooks/meta/genres")
    }

    func getSeries() async throws -> [SeriesInfo] {
        try await request("api/audiobooks/meta/series")
    }

    func getAuthors() async throws -> [AuthorInfo] {
        try await request("api/audiobooks/meta/authors")
    }

    func getAudiobooksByGenre(_ genre: String) async throws -> [Audiobook] {
        let response: AudiobooksResponse = try await request("api/audiobooks", queryItems: [
            URLQueryItem(name: "genre", value: genre)
        ])
        return response.audiobooks
    }

    func getAudiobooksBySeries(_ series: String) async throws -> [Audiobook] {
        let response: AudiobooksResponse = try await request("api/audiobooks", queryItems: [
            URLQueryItem(name: "series", value: series)
        ])
        return response.audiobooks
    }

    func getAudiobooksByAuthor(_ author: String) async throws -> [Audiobook] {
        let response: AudiobooksResponse = try await request("api/audiobooks", queryItems: [
            URLQueryItem(name: "author", value: author)
        ])
        return response.audiobooks
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

    func markFinished(audiobookId: Int) async throws {
        let body = ProgressUpdateRequest(position: 0, completed: 1, state: "stopped")
        try await requestVoid("api/audiobooks/\(audiobookId)/progress", method: "POST", body: body)
    }

    // MARK: - Chapters

    func getChapters(audiobookId: Int) async throws -> [Chapter] {
        try await request("api/audiobooks/\(audiobookId)/chapters")
    }

    // MARK: - Favorites

    func getFavorites(sort: String = "custom") async throws -> [Audiobook] {
        try await request("api/audiobooks/favorites", queryItems: [
            URLQueryItem(name: "sort", value: sort)
        ])
    }

    func toggleFavorite(audiobookId: Int) async throws -> FavoriteResponse {
        try await request("api/audiobooks/\(audiobookId)/favorite/toggle", method: "POST")
    }

    func removeFavorite(audiobookId: Int) async throws {
        try await requestVoid("api/audiobooks/\(audiobookId)/favorite", method: "DELETE")
    }

    func reorderFavorites(order: [Int]) async throws {
        try await requestVoid("api/audiobooks/favorites/reorder", method: "PUT", body: ["order": order])
    }

    // MARK: - Collections

    func getCollections() async throws -> [Collection] {
        try await request("api/collections")
    }

    func getCollection(id: Int) async throws -> CollectionDetail {
        try await request("api/collections/\(id)")
    }

    func createCollection(name: String, description: String? = nil, isPublic: Bool = false) async throws -> Collection {
        let body = CreateCollectionRequest(name: name, description: description, isPublic: isPublic)
        return try await request("api/collections", method: "POST", body: body)
    }

    func deleteCollection(id: Int) async throws {
        try await requestVoid("api/collections/\(id)", method: "DELETE")
    }

    func addToCollection(collectionId: Int, audiobookId: Int) async throws {
        let body = AddToCollectionRequest(audiobookId: audiobookId)
        try await requestVoid("api/collections/\(collectionId)/items", method: "POST", body: body)
    }

    func removeFromCollection(collectionId: Int, audiobookId: Int) async throws {
        try await requestVoid("api/collections/\(collectionId)/items/\(audiobookId)", method: "DELETE")
    }

    func getCollectionsForBook(audiobookId: Int) async throws -> [CollectionForBook] {
        try await request("api/collections/for-book/\(audiobookId)")
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

    func uploadAvatar(imageData: Data) async throws {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: "api/profile/avatar", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = authRepository.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data())

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    func deleteAvatar() async throws {
        try await requestVoid("api/profile/avatar", method: "DELETE")
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

    // MARK: - Admin: Users

    func getUsers() async throws -> [AdminUser] {
        try await request("api/users")
    }

    func createUser(username: String, password: String, isAdmin: Bool) async throws -> AdminUser {
        let body = CreateUserRequest(username: username, password: password, isAdmin: isAdmin)
        return try await request("api/users", method: "POST", body: body)
    }

    func deleteUser(id: Int) async throws {
        try await requestVoid("api/users/\(id)", method: "DELETE")
    }

    func toggleUserAdmin(id: Int, isAdmin: Bool) async throws {
        let body = UpdateUserRequest(isAdmin: isAdmin)
        try await requestVoid("api/users/\(id)", method: "PUT", body: body)
    }

    // MARK: - Admin: Maintenance

    func scanLibrary() async throws -> ScanResponse {
        try await request("api/maintenance/scan", method: "POST")
    }

    func forceRescan() async throws -> ScanResponse {
        try await request("api/maintenance/force-rescan", method: "POST")
    }

    // MARK: - Upload

    func uploadAudiobook(fileData: Data, fileName: String, mimeType: String, title: String?, author: String?, narrator: String?, onProgress: @escaping (Double) -> Void) async throws -> UploadResponse {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: "api/upload", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = authRepository.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // File part
        body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(fileData)
        body.append("\r\n".data(using: .utf8) ?? Data())

        // Optional metadata
        if let title, !title.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
            body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8) ?? Data())
            body.append("\(title)\r\n".data(using: .utf8) ?? Data())
        }
        if let author, !author.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
            body.append("Content-Disposition: form-data; name=\"author\"\r\n\r\n".data(using: .utf8) ?? Data())
            body.append("\(author)\r\n".data(using: .utf8) ?? Data())
        }
        if let narrator, !narrator.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
            body.append("Content-Disposition: form-data; name=\"narrator\"\r\n\r\n".data(using: .utf8) ?? Data())
            body.append("\(narrator)\r\n".data(using: .utf8) ?? Data())
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(UploadResponse.self, from: data)
    }

    // MARK: - URL Builders

    var authHeaders: [String: String] {
        guard let token = authRepository.token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    func coverURL(for audiobookId: Int) -> URL? {
        guard let baseURL = authRepository.serverURL else { return nil }
        return baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/cover")
    }

    func streamURL(for audiobookId: Int) -> URL? {
        guard let baseURL = authRepository.serverURL else { return nil }
        return baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/stream")
    }

    func avatarURL() -> URL? {
        guard let baseURL = authRepository.serverURL else { return nil }
        return baseURL.appendingPathComponent("api/profile/avatar")
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

private struct CreateCollectionRequest: Codable {
    let name: String
    let description: String?
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case isPublic = "is_public"
    }
}

private struct AddToCollectionRequest: Codable {
    let audiobookId: Int

    enum CodingKeys: String, CodingKey {
        case audiobookId = "audiobook_id"
    }
}

private struct CreateUserRequest: Codable {
    let username: String
    let password: String
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case username, password
        case isAdmin = "is_admin"
    }
}

private struct UpdateUserRequest: Codable {
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case isAdmin = "is_admin"
    }
}
