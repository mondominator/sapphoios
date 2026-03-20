import Foundation

struct ListeningSession: Codable, Identifiable {
    let id: Int
    let startedAt: String
    let stoppedAt: String?
    let startPosition: Int
    let endPosition: Int?
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
        case startPosition = "start_position"
        case endPosition = "end_position"
        case deviceName = "device_name"
    }
}

struct ListeningSessionsResponse: Codable {
    let sessions: [ListeningSession]
}
