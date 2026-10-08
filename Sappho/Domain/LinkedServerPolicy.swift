import Foundation

// Rules for books mirrored from a linked Sappho server (server 0.16+). A
// remote book has an ordinary integer id and uses the same endpoints as a
// local one; only its `source`, `available` flag and a few error codes differ.

/// The library's Source filter: everything, only this server's books, or one
/// linked server's books. Sent as `?source=` (all = omitted).
enum SourceFilter: Hashable {
    case all
    case local
    case server(id: Int, name: String)

    /// The `source` query value; nil for `.all`, so the parameter is omitted
    /// (older servers would ignore it anyway).
    var queryValue: String? {
        switch self {
        case .all: return nil
        case .local: return "local"
        case .server(let id, _): return String(id)
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .local: return "This server"
        case .server(_, let name): return name
        }
    }

    /// The menu's choices: All, This server, then each linked server. Empty
    /// when there are no linked servers, so the filter is not shown at all.
    static func options(for sources: [LinkedSource]) -> [SourceFilter] {
        guard !sources.isEmpty else { return [] }
        return [.all, .local] + sources.map { .server(id: $0.id, name: $0.name) }
    }
}

enum LinkedServerPolicy {
    /// Edit, delete, convert, metadata refresh/embed and chapter editing are
    /// refused for a remote book (409 REMOTE_BOOK_READ_ONLY), so hide them.
    static func canEdit(_ book: Audiobook, isAdmin: Bool) -> Bool {
        isAdmin && !book.isRemote
    }

    /// A downloaded book plays from its file whatever the server says.
    static func isPlayable(_ book: Audiobook, isDownloaded: Bool) -> Bool {
        isDownloaded || book.isAvailable
    }

    /// Why an unavailable book can't be played, for the user.
    static func unavailableMessage(for book: Audiobook) -> String {
        if let source = book.source {
            return "\(source.name)'s library is offline right now. Try again later."
        }
        return "This book's file is missing on the server."
    }

    /// The player's final message after a stream failed. A remote book is
    /// relayed by our server, so a failure that isn't a network error on our
    /// side is most likely the linked server.
    static func playbackFailureMessage(for book: Audiobook?, isNetworkError: Bool) -> String {
        if isNetworkError {
            return "Can't reach the server. Check your connection and try again."
        }
        if let source = book?.source {
            return "Couldn't play this book from \(source.name)'s library. It may be offline; try again later."
        }
        return "Playback failed. Try again."
    }

    /// A friendly message for the linked-server error codes; nil for any
    /// other code (the server's own message is used then).
    static func message(forErrorCode code: String?) -> String? {
        switch code {
        case "REMOTE_UNAVAILABLE":
            return "The linked library this book comes from is offline right now. Try again later."
        case "REMOTE_AUTH_FAILED":
            return "This server can no longer sign in to the linked library. An admin needs to fix the link."
        case "REMOTE_ERROR", "REMOTE_INVALID":
            return "The linked library this book comes from had a problem. Try again later."
        case "REMOTE_BOOK_GONE":
            return "This book is no longer available from the linked library."
        case "REMOTE_BOOK_READ_ONLY":
            return "Books from a linked library can't be changed here."
        default:
            return nil
        }
    }
}
