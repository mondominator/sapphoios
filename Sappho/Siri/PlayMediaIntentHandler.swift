import Intents

/// Siri's "play <book> on Sappho" -- the search CarPlay allows an audio app
/// (CPSearchTemplate is navigation-only; see CarPlaySceneDelegate). The car's
/// Siri button lands here; the phone gets the same request from Siri anywhere.
///
/// Resolving picks the book (`VoiceSearch`) from a server search, falling back
/// on the downloads when the server can't answer in time; handling asks iOS to
/// open the app in the background (`.handleInApp`), where AppDelegate starts
/// playback exactly as a CarPlay tap does.
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    static let shared = PlayMediaIntentHandler()

    /// Books resolved for recent requests, so playing one needn't fetch it again.
    @MainActor private var resolved: [Int: Audiobook] = [:]

    /// A car's link is slow; past this Siri gives up on us anyway.
    private static let searchTimeout: TimeInterval = 6

    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        let search = intent.mediaSearch
        guard let book = await findBook(mediaName: search?.mediaName, artistName: search?.artistName) else {
            return [.unsupported()]
        }
        await MainActor.run { resolved[book.id] = book }
        let item = INMediaItem(
            identifier: String(book.id),
            title: book.title,
            type: .audioBook,
            artwork: nil,
            artist: book.author
        )
        return INPlayMediaMediaItemResolutionResult.successes(with: [item])
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil)
    }

    /// The book to play for a resolved request, or nil.
    @MainActor
    func book(for intent: INPlayMediaIntent) async -> Audiobook? {
        guard let id = intent.mediaItems?.first?.identifier.flatMap(Int.init) else { return nil }
        if let book = resolved[id] { return book }
        if let downloaded = DownloadManager.shared.cachedMeta[id]?.toAudiobook() { return downloaded }
        return try? await ServiceLocator.shared.api?.getAudiobook(id: id)
    }

    // MARK: - Finding the book

    @MainActor
    private func findBook(mediaName: String?, artistName: String?) async -> Audiobook? {
        let downloaded = DownloadManager.shared.downloadedAudiobooks()
        guard let query = VoiceSearch.query(mediaName: mediaName, artistName: artistName) else {
            return currentBook(downloaded: downloaded)
        }
        var candidates: [Audiobook] = []
        if NetworkMonitor.shared.isConnected, let api = ServiceLocator.shared.api {
            candidates = (try? await Deadline.run(seconds: Self.searchTimeout) {
                try await api.getAudiobooks(search: query, limit: 25)
            }) ?? []
        }
        // Downloads always count: they are what plays with no signal, and a
        // search that timed out shouldn't mean "no such book".
        return VoiceSearch.bestMatch(query, in: candidates + downloaded)
    }

    /// "Play my audiobook": the loaded book, else the last one played.
    @MainActor
    private func currentBook(downloaded: [Audiobook]) -> Audiobook? {
        CarPlayHomeLayout.currentBook(
            loaded: ServiceLocator.shared.audioPlayer?.currentAudiobook,
            lastPlayedId: AudioPlayerService.lastPlayedAudiobookId,
            downloaded: downloaded,
            feed: HomeFeedStore.shared.sections
        )
    }
}
