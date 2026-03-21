import XCTest
@testable import Sappho

final class ListeningSessionTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Full JSON Decoding

    func testFullJSONDecoding() throws {
        let json = """
        {
            "id": 1,
            "started_at": "2025-03-15T10:30:00Z",
            "stopped_at": "2025-03-15T11:00:00Z",
            "start_position": 120,
            "end_position": 1920,
            "device_name": "iPhone 15 Pro"
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 1)
        XCTAssertEqual(session.startedAt, "2025-03-15T10:30:00Z")
        XCTAssertEqual(session.stoppedAt, "2025-03-15T11:00:00Z")
        XCTAssertEqual(session.startPosition, 120)
        XCTAssertEqual(session.endPosition, 1920)
        XCTAssertEqual(session.deviceName, "iPhone 15 Pro")
    }

    // MARK: - Minimal JSON Decoding

    func testMinimalJSONDecoding() throws {
        let json = """
        {
            "id": 5,
            "started_at": "2025-01-01T00:00:00Z",
            "start_position": 0
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 5)
        XCTAssertEqual(session.startedAt, "2025-01-01T00:00:00Z")
        XCTAssertEqual(session.startPosition, 0)
        XCTAssertNil(session.stoppedAt)
        XCTAssertNil(session.endPosition)
        XCTAssertNil(session.deviceName)
    }

    // MARK: - Missing Optional Fields

    func testMissingStoppedAt() throws {
        let json = """
        {
            "id": 10,
            "started_at": "2025-06-01T08:00:00Z",
            "start_position": 500,
            "end_position": 800,
            "device_name": "iPad Air"
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 10)
        XCTAssertNil(session.stoppedAt)
        XCTAssertEqual(session.endPosition, 800)
        XCTAssertEqual(session.deviceName, "iPad Air")
    }

    func testMissingEndPosition() throws {
        let json = """
        {
            "id": 11,
            "started_at": "2025-06-01T09:00:00Z",
            "stopped_at": "2025-06-01T09:30:00Z",
            "start_position": 0
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 11)
        XCTAssertEqual(session.stoppedAt, "2025-06-01T09:30:00Z")
        XCTAssertNil(session.endPosition)
        XCTAssertNil(session.deviceName)
    }

    func testMissingDeviceName() throws {
        let json = """
        {
            "id": 12,
            "started_at": "2025-07-01T12:00:00Z",
            "stopped_at": "2025-07-01T12:45:00Z",
            "start_position": 300,
            "end_position": 3000
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 12)
        XCTAssertEqual(session.startPosition, 300)
        XCTAssertEqual(session.endPosition, 3000)
        XCTAssertNil(session.deviceName)
    }

    func testAllOptionalFieldsMissing() throws {
        let json = """
        {
            "id": 99,
            "started_at": "2025-12-25T00:00:00Z",
            "start_position": 42
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        XCTAssertEqual(session.id, 99)
        XCTAssertEqual(session.startedAt, "2025-12-25T00:00:00Z")
        XCTAssertEqual(session.startPosition, 42)
        XCTAssertNil(session.stoppedAt)
        XCTAssertNil(session.endPosition)
        XCTAssertNil(session.deviceName)
    }

    // MARK: - ListeningSessionsResponse Decoding

    func testListeningSessionsResponseDecoding() throws {
        let json = """
        {
            "sessions": [
                {
                    "id": 1,
                    "started_at": "2025-03-15T10:00:00Z",
                    "stopped_at": "2025-03-15T10:30:00Z",
                    "start_position": 0,
                    "end_position": 1800,
                    "device_name": "iPhone"
                },
                {
                    "id": 2,
                    "started_at": "2025-03-16T14:00:00Z",
                    "start_position": 1800
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ListeningSessionsResponse.self, from: json)

        XCTAssertEqual(response.sessions.count, 2)

        XCTAssertEqual(response.sessions[0].id, 1)
        XCTAssertEqual(response.sessions[0].startPosition, 0)
        XCTAssertEqual(response.sessions[0].endPosition, 1800)
        XCTAssertEqual(response.sessions[0].deviceName, "iPhone")

        XCTAssertEqual(response.sessions[1].id, 2)
        XCTAssertEqual(response.sessions[1].startPosition, 1800)
        XCTAssertNil(response.sessions[1].stoppedAt)
        XCTAssertNil(response.sessions[1].endPosition)
        XCTAssertNil(response.sessions[1].deviceName)
    }

    func testListeningSessionsResponseEmptySessions() throws {
        let json = """
        {
            "sessions": []
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ListeningSessionsResponse.self, from: json)

        XCTAssertTrue(response.sessions.isEmpty)
    }

    func testListeningSessionIdentifiable() throws {
        let json = """
        {
            "id": 77,
            "started_at": "2025-01-01T00:00:00Z",
            "start_position": 0
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        // Identifiable conformance: id should match
        XCTAssertEqual(session.id, 77)
    }

    func testListeningSessionEncoding() throws {
        let json = """
        {
            "id": 3,
            "started_at": "2025-05-01T15:00:00Z",
            "stopped_at": "2025-05-01T15:45:00Z",
            "start_position": 600,
            "end_position": 3300,
            "device_name": "MacBook Pro"
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(ListeningSession.self, from: json)

        // Encode back to JSON and decode again to verify round-trip
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(session)
        let decoded = try decoder.decode(ListeningSession.self, from: encodedData)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.startedAt, session.startedAt)
        XCTAssertEqual(decoded.stoppedAt, session.stoppedAt)
        XCTAssertEqual(decoded.startPosition, session.startPosition)
        XCTAssertEqual(decoded.endPosition, session.endPosition)
        XCTAssertEqual(decoded.deviceName, session.deviceName)
    }
}
