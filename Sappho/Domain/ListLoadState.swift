import Foundation

/// What a list screen shows while it loads. Only the first load may replace
/// the list with a spinner or an error screen. Later reloads (each time the
/// screen reappears, and pull to refresh) update the list in place, so coming
/// back from a book or an author lands where you left the list instead of at
/// the top: swapping the list for a spinner threw its scroll position away.
struct ListLoadState: Equatable {
    private(set) var hasLoaded = false
    private(set) var isLoading = true
    private(set) var lastError: String?

    /// Full-screen spinner: only until the first load succeeds.
    var showsSpinner: Bool { isLoading && !hasLoaded }

    /// Full-screen error: only when there is nothing loaded to show instead.
    /// A failed reload keeps the list that is already on screen.
    var blockingError: String? { hasLoaded || isLoading ? nil : lastError }

    mutating func begin() {
        isLoading = true
        lastError = nil
    }

    mutating func failed(_ message: String) {
        lastError = message
    }

    mutating func end() {
        isLoading = false
        if lastError == nil { hasLoaded = true }
    }
}
