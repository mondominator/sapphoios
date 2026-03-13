import XCTest
@testable import Sappho

final class APIErrorTests: XCTestCase {

    // MARK: - Error Descriptions

    func testInvalidURLDescription() {
        let error = APIError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid URL")
    }

    func testNotAuthenticatedDescription() {
        let error = APIError.notAuthenticated
        XCTAssertEqual(error.errorDescription, "Not authenticated")
    }

    func testInvalidResponseDescription() {
        let error = APIError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid server response")
    }

    func testHTTPErrorWithMessage() {
        let error = APIError.httpError(statusCode: 404, message: "Not Found")
        XCTAssertEqual(error.errorDescription, "Not Found")
    }

    func testHTTPErrorWithoutMessage() {
        let error = APIError.httpError(statusCode: 500, message: nil)
        XCTAssertEqual(error.errorDescription, "HTTP error 500")
    }

    func testDecodingErrorDescription() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing key"])
        let error = APIError.decodingError(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Failed to decode response") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("missing key") ?? false)
    }

    func testNetworkErrorDescription() {
        let underlyingError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        let error = APIError.networkError(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Network error") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("offline") ?? false)
    }

    // MARK: - LocalizedError Conformance

    func testConformsToLocalizedError() {
        let error: Error = APIError.invalidURL
        XCTAssertNotNil(error.localizedDescription)
        XCTAssertEqual(error.localizedDescription, "Invalid URL")
    }

    func testHTTPErrorCommonStatusCodes() {
        let cases: [(Int, String?)] = [
            (400, "Bad Request"),
            (401, "Unauthorized"),
            (403, "Forbidden"),
            (404, nil),
            (500, nil),
        ]

        for (code, message) in cases {
            let error = APIError.httpError(statusCode: code, message: message)
            let description = error.errorDescription ?? ""
            if let message = message {
                XCTAssertEqual(description, message, "Expected message for status \(code)")
            } else {
                XCTAssertTrue(description.contains("\(code)"), "Expected status code \(code) in description")
            }
        }
    }

    // MARK: - Error is Error Protocol

    func testAPIErrorIsSwiftError() {
        let errors: [APIError] = [
            .invalidURL,
            .notAuthenticated,
            .invalidResponse,
            .httpError(statusCode: 500, message: nil),
            .decodingError(NSError(domain: "test", code: 0)),
            .networkError(NSError(domain: "test", code: 0)),
        ]

        for error in errors {
            // Verify each case can be used as a generic Error
            let genericError: Error = error
            XCTAssertFalse(genericError.localizedDescription.isEmpty)
        }
    }
}
