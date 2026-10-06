import Foundation

/// What CarPlay's Home shows, decided without CarPlay types so it can be
/// unit tested. `CarPlayContentProvider` turns it into CPListSections.
///
/// Rules:
/// - Something is on screen from the first frame: the current book, the
///   downloaded books and the last saved feed need no network.
/// - When the feed can't be trusted to be current (offline, or nothing has
///   answered yet), downloaded books come straight after Resume: they are
///   what will actually play.
/// - A section that failed to refresh keeps its saved books; a status row
///   says the feed couldn't refresh and offers a retry. Nothing goes blank.
struct CarPlayHomeSection: Equatable {
    var header: String?
    var rows: [CarPlayHomeRow]
}

enum CarPlayHomeRow: Equatable {
    case book(Audiobook, isDownloaded: Bool)
    case status(title: String, detail: String?, retry: Bool)

    static func == (lhs: CarPlayHomeRow, rhs: CarPlayHomeRow) -> Bool {
        switch (lhs, rhs) {
        case let (.book(a, da), .book(b, db)):
            return a.id == b.id && da == db
        case let (.status(t1, d1, r1), .status(t2, d2, r2)):
            return t1 == t2 && d1 == d2 && r1 == r2
        default:
            return false
        }
    }

    var bookId: Int? {
        if case .book(let book, _) = self { return book.id }
        return nil
    }
}

enum CarPlayHomeLayout {
    /// CarPlay caps list length; a car is no place to scroll 100 rows anyway.
    static let maxRowsPerSection = 25

    static let resumeHeader = "Resume"
    static let inProgressHeader = "In Progress"
    static let downloadedHeader = "Downloaded"

    /// The book to offer as Resume: the one loaded in the player, else the
    /// last one played (looked up in the downloads, then the saved feed) --
    /// a cold start in the car has nothing loaded yet, and fetching it from
    /// the server is exactly what a slow link can't do.
    static func currentBook(
        loaded: Audiobook?,
        lastPlayedId: Int?,
        downloaded: [Audiobook],
        feed: [HomeSectionKind: HomeSectionState]
    ) -> Audiobook? {
        if let loaded { return loaded }
        guard let lastPlayedId, lastPlayedId > 0 else { return nil }
        if let book = downloaded.first(where: { $0.id == lastPlayedId }) { return book }
        for kind in HomeSectionKind.allCases {
            if let book = feed[kind]?.books.first(where: { $0.id == lastPlayedId }) { return book }
        }
        return nil
    }

    static func build(
        feed: [HomeSectionKind: HomeSectionState],
        downloaded: [Audiobook],
        current: Audiobook?,
        isConnected: Bool
    ) -> [CarPlayHomeSection] {
        let downloadedIds = Set(downloaded.map(\.id))
        func row(_ book: Audiobook) -> CarPlayHomeRow {
            .book(book, isDownloaded: downloadedIds.contains(book.id))
        }
        func books(_ kind: HomeSectionKind) -> [Audiobook] { feed[kind]?.books ?? [] }

        let states = HomeSectionKind.allCases.map { feed[$0] ?? HomeSectionState() }
        let anyLoaded = states.contains { $0.status == .loaded }
        let anyLoading = states.contains { $0.status == .loading || $0.status == .notLoaded }
        let failed = states.filter { if case .failed = $0.status { return true } else { return false } }
        let allFailedOffline = !failed.isEmpty && failed.count == states.count
            && failed.allSatisfy { if case .failed(let f) = $0.status { return f.isConnectivity } else { return false } }
        // Offline, or nothing current yet: lead with what plays without a server.
        let downloadsFirst = !isConnected || !anyLoaded

        // Resume: the current book, else the first in progress. Offline, a
        // book that isn't downloaded can't play, so it isn't offered on top.
        let inProgress = books(.continueListening)
        var resume = current ?? inProgress.first
        if let book = resume, !isConnected, !downloadedIds.contains(book.id) {
            resume = nil
        }
        let resumeId = resume?.id

        var sections: [CarPlayHomeSection] = []
        if let resume {
            sections.append(CarPlayHomeSection(header: resumeHeader, rows: [row(resume)]))
        }

        let downloadedSection = CarPlayHomeSection(
            header: downloadedHeader,
            rows: downloaded.filter { $0.id != resumeId }.prefix(maxRowsPerSection).map(row)
        )

        if downloadsFirst, !downloadedSection.rows.isEmpty {
            sections.append(downloadedSection)
        }

        let feedSections: [(String, [Audiobook])] = [
            (inProgressHeader, inProgress.filter { $0.id != resumeId }),
            (HomeSectionKind.upNext.title, books(.upNext)),
            (HomeSectionKind.recentlyAdded.title, books(.recentlyAdded)),
            (HomeSectionKind.listenAgain.title, books(.listenAgain))
        ]
        for (header, list) in feedSections where !list.isEmpty {
            sections.append(CarPlayHomeSection(header: header, rows: list.prefix(maxRowsPerSection).map(row)))
        }

        if !downloadsFirst, !downloadedSection.rows.isEmpty {
            sections.append(downloadedSection)
        }

        // Status: never a blank screen, and say when the feed is stale.
        if sections.isEmpty {
            if isConnected && anyLoading {
                sections.append(CarPlayHomeSection(header: nil, rows: [
                    .status(title: "Loading your library…", detail: nil, retry: false)
                ]))
            } else if isConnected && !allFailedOffline && failed.isEmpty {
                sections.append(CarPlayHomeSection(header: nil, rows: [
                    .status(title: "Nothing in progress", detail: "Start a book from Library.", retry: false)
                ]))
            } else {
                sections.append(CarPlayHomeSection(header: nil, rows: [
                    .status(title: "Can't reach your Sappho server",
                            detail: "Downloaded books appear here when you're offline. Tap to retry.",
                            retry: true)
                ]))
            }
        } else if !isConnected {
            sections.append(CarPlayHomeSection(header: nil, rows: [
                .status(title: "Offline", detail: "Showing downloaded and saved books.", retry: false)
            ]))
        } else if !failed.isEmpty {
            sections.append(CarPlayHomeSection(header: nil, rows: [
                .status(title: "Couldn't refresh", detail: "Showing saved books. Tap to retry.", retry: true)
            ]))
        }

        return sections
    }
}

// MARK: - Starting playback from a tap

/// What CarPlay needs from the player to start a book.
@MainActor
protocol CarPlayPlaybackTarget: AnyObject {
    func play(audiobook: Audiobook, startPosition: TimeInterval?) async
    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval) async
}

extension AudioPlayerService: CarPlayPlaybackTarget {}

enum CarPlayPlaybackStarter {
    /// Show Now Playing and start the book with what the device already has.
    /// Nothing here waits on the network: the server's copy of the book is
    /// fetched only after playback has started (`refreshAfterImmediateStart`).
    @MainActor
    @discardableResult
    static func start(
        _ book: Audiobook,
        downloaded: Audiobook?,
        player: CarPlayPlaybackTarget,
        showNowPlaying: () -> Void,
        refreshTimeout: TimeInterval = 15
    ) -> Task<Void, Never> {
        let toPlay = CarPlayPlaybackPlan.bookToPlay(tapped: book, downloaded: downloaded)
        showNowPlaying()
        return Task { @MainActor in
            await player.play(audiobook: toPlay, startPosition: nil)
            await player.refreshAfterImmediateStart(audiobookId: toPlay.id, timeout: refreshTimeout)
        }
    }
}
