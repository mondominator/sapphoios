import Foundation
import AVFoundation
import MediaPlayer

/// Holds NotificationCenter observer tokens and removes them when deallocated.
/// Lives outside the @MainActor service so its (nonisolated) deinit can run
/// the cleanup without touching main-actor-isolated state.
private final class NotificationTokenBag {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
@Observable
class AudioPlayerService: NSObject {
    // MARK: - Public State
    var showFullPlayer: Bool = false
    var currentAudiobook: Audiobook?
    var currentChapter: Chapter?
    var isPlaying: Bool = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackSpeed: Float = 1.0
    /// Waiting for audio (a stream starting or stalled). Reflected in Now
    /// Playing so the lock screen and CarPlay don't show a running clock.
    var isBuffering: Bool = false {
        didSet {
            if isBuffering != oldValue { updateNowPlayingInfo() }
        }
    }
    var sleepTimerRemaining: TimeInterval?
    /// A user-facing playback problem (stream failed, file ended early). The
    /// player and mini player show it with a Retry button. Nil when healthy.
    var playbackError: String?

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    /// Block-based KVO on the current item (status, buffering). Replaced
    /// whenever the item is, which drops the old observations with it.
    private var itemObservations: [NSKeyValueObservation] = []
    /// Notification observers scoped to the current item (failed / stalled).
    private var itemNotificationTokens: [NSObjectProtocol] = []
    /// One automatic rebuild per play request; a second failure is shown
    /// (and reset by Retry, resume or playing another book), so a server that
    /// keeps failing can't trap the player in a rebuild loop.
    private var hasRetriedCurrentItem = false
    /// Whether the current item plays a downloaded file rather than the stream.
    private var isPlayingLocalFile = false
    /// How the current item gets its audio, and from where (`StreamingPolicy`).
    private(set) var streamMode: StreamMode?
    private(set) var streamURL: URL?
    /// The network the stream choice is made for. Injectable for tests.
    var networkConditions: () -> NetworkConditions = { NetworkMonitor.shared.conditions }
    /// HLS failed for this play request in a way a reload can't fix: the rest
    /// of it uses `/stream`. Reset by the next play().
    private var hlsBlockedForCurrentPlay = false
    /// HLS reloads (file changed, token refreshed) in this play request.
    private var hlsReloads = 0
    private var isRecoveringHLS = false
    /// Books the server answered 415 for (not AAC in MP4), so they go
    /// straight to `/stream` next time. Cleared on logout.
    private var hlsUnsupportedBookIds: Set<Int> = []
    /// When playback was last paused, so a long-paused stream can be rebuilt
    /// with fresh auth headers before resuming.
    private var pausedAt: Date?
    /// A paused stream older than this is rebuilt on resume: its request
    /// headers carry the token from when it was created, and access tokens
    /// expire (7 days on the server), after which range requests get 401.
    private let staleStreamInterval: TimeInterval = 30 * 60
    private let progressStore = ProgressStore()
    /// Where the current play request started, for `LateProgressPolicy`.
    private var playStartedAt: TimeInterval = 0
    /// The cover URL whose artwork download is in flight, so the periodic
    /// Now Playing refresh doesn't start another one every few seconds.
    private var artworkFetchKey: String?
    private var didStartRestore = false
    /// Notification observer tokens; removed automatically when the bag deallocates,
    /// so no main-actor-isolated cleanup is needed in deinit.
    private let notificationTokens = NotificationTokenBag()

    private var api: SapphoAPI?
    private var lastSyncPosition: Int = 0
    private let syncThreshold: Int = 20 // Sync every 20 seconds (matching Android)
    private var lastSavePosition: Int = 0

    // Persistence keys
    private static let lastAudiobookIdKey = "lastPlayedAudiobookId"

    /// The book last played on this device, if any (saved, so it survives a
    /// relaunch; CarPlay offers it as Resume before anything is loaded).
    nonisolated static var lastPlayedAudiobookId: Int? {
        let id = UserDefaults.standard.integer(forKey: lastAudiobookIdKey)
        return id > 0 ? id : nil
    }
    private static let lastPositionKey = "lastPlayedPosition"
    private static let playbackSpeedKey = "playbackSpeed"

    // MARK: - Initialization

    override init() {
        super.init()
        let savedSpeed = UserDefaults.standard.float(forKey: Self.playbackSpeedKey)
        if savedSpeed > 0 {
            playbackSpeed = savedSpeed
        }
        setupAudioSession()
        setupRemoteCommands()
        setupInterruptionHandling()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .longFormAudio,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func configure(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Playback Controls

    /// Creates the player item (with auth headers for remote streams), registers
    /// buffering KVO, and creates the AVPlayer. Shared by play() and resume().
    /// Returns false if no stream URL could be determined.
    private func setUpPlayer(for audiobook: Audiobook) -> Bool {
        // A downloaded book plays its file; a stream is progressive or HLS
        // depending on the network and the data saver setting. Decided per
        // item, so a rebuild (failure, long pause) picks up a network change;
        // both modes share one timeline, so the position carries over.
        let localURL = DownloadManager.shared.localURL(for: audiobook.id)
        let mode = StreamingPolicy.mode(
            isDownloaded: localURL != nil,
            network: networkConditions(),
            dataSaver: UserDefaults.standard.bool(forKey: StreamingPolicy.dataSaverKey),
            codec: hlsUnsupportedBookIds.contains(audiobook.id) ? .unsupported : HLSCodecHint.from(filePath: audiobook.filePath),
            hlsBlocked: hlsBlockedForCurrentPlay
        )
        guard let streamURL = localURL ?? api?.streamURL(for: audiobook.id, mode: mode) else { return false }
        isPlayingLocalFile = localURL != nil
        self.streamMode = mode
        self.streamURL = streamURL

        // Create player item — use auth headers for remote streams. AVPlayer
        // sends them on every HLS request too (master, media playlists, init
        // and segments). The headers are read now, so a rebuild (see
        // rebuildCurrentItem) is the only way to give a long-lived stream a
        // refreshed token.
        let asset: AVURLAsset
        if isPlayingLocalFile {
            asset = AVURLAsset(url: streamURL)
        } else {
            let headers = api?.authHeaders ?? [:]
            asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        let item = AVPlayerItem(asset: asset)
        // Spectral time-stretching keeps voices clean above 1x; the default
        // algorithm warbles noticeably on speech at 1.25x and up.
        item.audioTimePitchAlgorithm = .spectral
        item.preferredPeakBitRate = StreamingPolicy.preferredPeakBitRate(for: mode)
        playerItem = item
        observe(item)

        // Create player
        player = AVPlayer(playerItem: item)
        player?.allowsExternalPlayback = false // Force local decode + AirPlay audio routing (external playback fails with auth headers)

        return true
    }

    /// Watch the item for failure and buffering. Nothing used to observe
    /// `status` or the failed/stalled notifications, so a stream that 401'd or
    /// a server that went away left the UI saying "playing" at a frozen
    /// position with no error.
    private func observe(_ item: AVPlayerItem) {
        stopObservingItem()

        itemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let status = item.status
                let error = item.error
                Task { @MainActor [weak self] in
                    guard let self, self.playerItem === item, status == .failed else { return }
                    self.handleItemFailure(error)
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                let empty = item.isPlaybackBufferEmpty
                Task { @MainActor [weak self] in
                    guard let self, self.playerItem === item, empty else { return }
                    self.isBuffering = true
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                let likely = item.isPlaybackLikelyToKeepUp
                Task { @MainActor [weak self] in
                    guard let self, self.playerItem === item, likely else { return }
                    self.isBuffering = false
                }
            }
        ]

        let center = NotificationCenter.default
        itemNotificationTokens = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                MainActor.assumeIsolated {
                    self?.handleItemFailure(error)
                }
            },
            center.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A stall is not a failure: AVPlayer resumes by itself
                    // once data arrives. Show it as buffering.
                    self?.isBuffering = true
                }
            }
        ]
    }

    private func stopObservingItem() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        itemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotificationTokens = []
    }

    /// The item failed (network gone, 401 on an expired token, 404). Try once
    /// to rebuild it with a refreshed token at the current position; if that
    /// fails too, stop claiming to play and tell the user.
    private func handleItemFailure(_ error: Error?) {
        let wasPlaying = isPlaying
        isPlaying = false
        isBuffering = false
        updateNowPlayingInfo()
        savePlaybackState()
        print("Playback failed: \(String(describing: error))")

        // HLS has its own recovery: reload the master if the file changed or
        // the token expired, else continue on /stream at the same position.
        if streamMode?.isHLS == true {
            guard !isRecoveringHLS else { return }
            isRecoveringHLS = true
            let event = playerItem?.errorLog()?.events.last
            // The error event often has no URI; the access log names the
            // media playlist that was playing (`/hls/<version>/<variant>/`).
            let failedVersion = HLSRecoveryPolicy.fileVersion(inURI: event?.uri)
                ?? HLSRecoveryPolicy.fileVersion(inURI: playerItem?.accessLog()?.events.last?.uri)
            let failedStatus = HLSRecoveryPolicy.httpStatus(comment: event?.errorComment, code: event?.errorStatusCode)
            Task {
                await recoverFromHLSFailure(failedVersion: failedVersion, failedStatusCode: failedStatus, andPlay: wasPlaying)
            }
            return
        }

        guard !hasRetriedCurrentItem else {
            playbackError = Self.describe(error)
            return
        }
        hasRetriedCurrentItem = true
        Task {
            await rebuildCurrentItem(andPlay: wasPlaying)
        }
    }

    private static func describe(_ error: Error?) -> String {
        if let error = error as NSError?, error.domain == NSURLErrorDomain {
            return "Can't reach the server. Check your connection and try again."
        }
        return "Playback failed. Try again."
    }

    /// AVPlayer failed on an HLS item. It does not expose the server's
    /// status or error body, so ask for the master playlist directly and
    /// decide: reload HLS (404 FILE_VERSION_CHANGED, expired token) or play
    /// `/stream` from the same position (415 HLS_UNSUPPORTED, anything else).
    private func recoverFromHLSFailure(failedVersion: String?, failedStatusCode: Int?, andPlay shouldPlay: Bool) async {
        guard let audiobook = currentAudiobook, let api else {
            isRecoveringHLS = false
            return
        }
        await api.ensureFreshToken()
        let probe = await api.probeHLSMaster(for: audiobook.id)
        guard currentAudiobook?.id == audiobook.id else {
            isRecoveringHLS = false
            return
        }

        if probe == .unsupported {
            hlsUnsupportedBookIds.insert(audiobook.id)
        }
        let action = HLSRecoveryPolicy.action(
            probe: probe,
            failedVersion: failedVersion,
            failedStatusCode: failedStatusCode,
            reloadsSoFar: hlsReloads
        )
        print("HLS failed (version \(failedVersion ?? "-"), status \(failedStatusCode.map(String.init) ?? "-"), probe \(probe)): \(action)")
        switch action {
        case .reloadHLS:
            hlsReloads += 1
        case .fallBackToProgressive:
            hlsBlockedForCurrentPlay = true
        }
        // The failed item's observers go with it in the rebuild; a failure of
        // the new item must be handled, not swallowed by the guard.
        isRecoveringHLS = false
        await rebuildCurrentItem(andPlay: shouldPlay, refreshToken: false)
    }

    /// Recreate the player item at the current position, with a token that
    /// has just been refreshed. Used after a failure and before resuming a
    /// stream that sat paused long enough for its token to expire.
    private func rebuildCurrentItem(andPlay shouldPlay: Bool, refreshToken: Bool = true) async {
        guard let audiobook = currentAudiobook else { return }
        let resumePosition = position
        if refreshToken, DownloadManager.shared.localURL(for: audiobook.id) == nil {
            await api?.ensureFreshToken()
        }
        // The book may have changed while the token refreshed.
        guard currentAudiobook?.id == audiobook.id else { return }

        stopTimeObserver()
        player?.pause()
        guard setUpPlayer(for: audiobook) else { return }
        if resumePosition > 0 {
            await seek(to: resumePosition)
        }
        startTimeObserver()
        if shouldPlay {
            player?.play()
            player?.rate = playbackSpeed
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    /// Retry after a playback error (the Retry button).
    func retryPlayback() {
        playbackError = nil
        hasRetriedCurrentItem = false
        Task {
            await rebuildCurrentItem(andPlay: true)
        }
    }

    func play(audiobook: Audiobook, startPosition: TimeInterval? = nil) async {
        // Play on the book that is already loaded continues it. Reloading
        // would seek to the caller's copy of the server position, which can be
        // an hour stale (the detail view fetched it when it opened), and the
        // next sync would then write that old position back to the server.
        if PlayRequestPolicy.shouldResumeLoadedBook(
            loadedBookId: currentAudiobook?.id,
            requestedBookId: audiobook.id,
            explicitStart: startPosition
        ) {
            guard !isPlaying else { return }
            // Still honour a newer position from another device: the caller's
            // copy of the server progress wins only if its timestamp is newer
            // than what this device saved.
            let target = TimeInterval(resolvedStartPosition(for: audiobook))
            if audiobook.progress != nil, abs(target - position) > 5 {
                if player != nil {
                    await seek(to: target)
                } else {
                    position = target
                }
            }
            resume()
            return
        }

        // Seek to the explicit start, else the newer of the server's position
        // and the one saved on this device. Resolved before stop(), which
        // clears the saved "last played" slot.
        let seekPosition = startPosition ?? TimeInterval(resolvedStartPosition(for: audiobook))

        // Stop current playback
        stop()

        // A download that no longer matches the server's file (replaced, or a
        // multi-file book since merged) must not be played; stream instead
        // while a fresh copy downloads.
        DownloadManager.shared.discardIfStale(for: audiobook)

        currentAudiobook = audiobook
        playbackError = nil
        hasRetriedCurrentItem = false
        hlsBlockedForCurrentPlay = false
        hlsReloads = 0
        isRecoveringHLS = false

        guard setUpPlayer(for: audiobook) else {
            print("Failed to get stream URL for audiobook \(audiobook.id)")
            return
        }

        // Get duration
        if let durationSeconds = audiobook.duration {
            duration = TimeInterval(durationSeconds)
        }

        // Say what is playing before waiting on anything. Seeking a stream
        // has to wait for the server (an .m4b with its index at the end of
        // the file needs that index first), and on a slow link that can take
        // a while: Now Playing (phone, lock screen, CarPlay) should show the
        // book and "buffering" meanwhile, not the previous book or nothing.
        position = seekPosition
        isPlaying = true
        isBuffering = !isPlayingLocalFile
        playStartedAt = seekPosition
        updateNowPlayingInfo()

        if seekPosition > 0 {
            await seek(to: seekPosition)
        }
        // Stopped, or another book started, while the seek waited.
        guard currentAudiobook?.id == audiobook.id else { return }

        // Start playback and apply user's speed setting (play() sets rate to
        // 1.0, so we must set playbackSpeed after) -- unless the listener
        // paused while the seek waited.
        if isPlaying {
            if StreamStartPolicy.startImmediately(isLocalFile: isPlayingLocalFile) {
                player?.playImmediately(atRate: playbackSpeed)
            } else {
                player?.play()
                player?.rate = playbackSpeed
            }
        }

        // Start time observer
        startTimeObserver()

        // Update now playing info
        updateNowPlayingInfo()

        // Load chapters if not already loaded
        if audiobook.chapters == nil || audiobook.chapters?.isEmpty == true {
            Task {
                do {
                    let chapters = try await api?.getChapters(audiobookId: audiobook.id)
                    // The fetch may complete after stop() or after another book
                    // started — don't resurrect a cleared/replaced book.
                    guard currentAudiobook?.id == audiobook.id else { return }
                    currentAudiobook = audiobook.withChapters(chapters)
                    // Cache chapters for offline playback
                    if let chapters = chapters {
                        DownloadManager.shared.cacheChapters(audiobookId: audiobook.id, chapters: chapters)
                    }
                } catch {
                    print("Failed to load chapters: \(error)")
                }
            }
        }
    }

    /// After a play that started from what the device already knew (CarPlay
    /// starts at once, without asking the server first), fetch the server's
    /// copy of the book in the background: pick up chapters, and a newer
    /// position from another device if the listener has barely started.
    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval = 15) async {
        guard let api, NetworkMonitor.shared.isConnected else { return }
        let localAtStart = api.accountKey.flatMap { progressStore.localProgress(account: $0, audiobookId: audiobookId) }
        let startedAt = playStartedAt
        guard let fresh = try? await Deadline.run(seconds: timeout, { try await api.getAudiobook(id: audiobookId) }),
              currentAudiobook?.id == audiobookId else { return }

        if currentAudiobook?.chapters?.isEmpty ?? true, let chapters = fresh.chapters, !chapters.isEmpty {
            currentAudiobook = currentAudiobook?.withChapters(chapters)
            updateCurrentChapter()
        }
        let serverPosition = ProgressReconciler.resolve(
            serverPosition: fresh.progress?.position,
            serverUpdatedAt: fresh.progress?.updatedAt,
            local: localAtStart
        )
        if let target = LateProgressPolicy.seekTarget(startedAt: startedAt, currentPosition: position, resolvedServerPosition: serverPosition) {
            await seek(to: target)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        pausedAt = Date()
        updateNowPlayingInfo()
        syncProgressToServer()
        savePlaybackState()
    }

    func resume() {
        guard currentAudiobook != nil else { return }
        playbackError = nil

        // A stream paused long enough may carry an expired token in its
        // request headers; rebuild it with a fresh one before playing.
        let streamWentStale = !isPlayingLocalFile
            && pausedAt.map { Date().timeIntervalSince($0) > staleStreamInterval } == true
        if player != nil, streamWentStale || playerItem?.status == .failed {
            self.pausedAt = nil
            Task {
                await rebuildCurrentItem(andPlay: true)
            }
            return
        }
        pausedAt = nil

        // Re-activate audio session in case it was deactivated
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }

        // If player was destroyed (e.g. app was killed and restored), recreate it
        if player == nil, let audiobook = currentAudiobook {
            let savedPosition = position
            Task {
                // Re-check inside the task: a rapid second resume() call spawns
                // its own task before this one runs, and setting up twice would
                // leak the first player and its KVO registrations.
                guard player == nil else { return }
                // Re-create player without calling stop() to avoid clearing currentAudiobook
                guard setUpPlayer(for: audiobook) else { return }

                if let durationSeconds = audiobook.duration {
                    duration = TimeInterval(durationSeconds)
                }
                if savedPosition > 0 {
                    await seek(to: savedPosition)
                }
                player?.play()
                player?.rate = playbackSpeed
                isPlaying = true
                startTimeObserver()
                updateNowPlayingInfo()
            }
            return
        }

        // Apply rewind-on-resume setting
        let rewindSeconds = UserDefaults.standard.integer(forKey: "rewindOnResume")
        if rewindSeconds > 0 && position > TimeInterval(rewindSeconds) {
            let newPosition = position - TimeInterval(rewindSeconds)
            Task {
                await seek(to: newPosition)
                player?.play()
                player?.rate = playbackSpeed
                isPlaying = true
                updateNowPlayingInfo()
            }
            return
        }

        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func stop(syncProgress: Bool = true) {
        if syncProgress {
            syncProgressToServer()
        }

        player?.pause()
        stopTimeObserver()
        stopObservingItem()

        player = nil
        playerItem = nil
        streamMode = nil
        streamURL = nil
        currentAudiobook = nil
        currentChapter = nil
        isPlaying = false
        position = 0
        duration = 0
        playbackError = nil
        isBuffering = false
        pausedAt = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        UserDefaults.standard.removeObject(forKey: Self.lastAudiobookIdKey)
        UserDefaults.standard.removeObject(forKey: Self.lastPositionKey)
    }

    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        // Exact in every mode, so a position resumes at the same spot on
        // progressive and HLS (see SeekPolicy).
        await player?.seek(to: cmTime, toleranceBefore: SeekPolicy.toleranceBefore, toleranceAfter: SeekPolicy.toleranceAfter)
        position = time
        updateNowPlayingInfo()
        updateCurrentChapter()
    }

    func skipForward(seconds: TimeInterval = 30) {
        let newPosition = min(position + seconds, duration)
        Task {
            await seek(to: newPosition)
        }
    }

    func skipBackward(seconds: TimeInterval = 15) {
        let newPosition = max(position - seconds, 0)
        Task {
            await seek(to: newPosition)
        }
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        UserDefaults.standard.set(speed, forKey: Self.playbackSpeedKey)
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    func jumpToChapter(_ chapter: Chapter) {
        Task {
            await seek(to: chapter.startTime)
        }
    }

    // MARK: - Sleep Timer

    var sleepAtEndOfChapter = false

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTimerRemaining = TimeInterval(minutes * 60)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer is scheduled from the main actor, so it fires on the main run loop.
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let remaining = self.sleepTimerRemaining {
                    if remaining <= 1 {
                        self.pause()
                        self.cancelSleepTimer()
                    } else {
                        self.sleepTimerRemaining = remaining - 1
                    }
                }
            }
        }
    }

    func setSleepTimerEndOfChapter() {
        cancelSleepTimer()
        sleepAtEndOfChapter = true
        sleepTimerRemaining = -1 // sentinel value to indicate active but chapter-based
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        sleepAtEndOfChapter = false
    }

    // MARK: - State Persistence

    private func savePlaybackState() {
        guard let audiobook = currentAudiobook else {
            UserDefaults.standard.removeObject(forKey: Self.lastAudiobookIdKey)
            UserDefaults.standard.removeObject(forKey: Self.lastPositionKey)
            return
        }
        let pos = Int(position)
        UserDefaults.standard.set(audiobook.id, forKey: Self.lastAudiobookIdKey)
        UserDefaults.standard.set(pos, forKey: Self.lastPositionKey)
        if let account = api?.accountKey {
            progressStore.saveLocal(account: account, audiobookId: audiobook.id, position: pos)
        }

        // Keep downloaded book metadata in sync
        DownloadManager.shared.updatePosition(audiobookId: audiobook.id, position: pos)
    }

    /// The position to start a book from: the newer of the server's position
    /// and the one this device saved (by timestamp). Local wins after offline
    /// listening or a kill within the 20 s sync interval; the server wins
    /// after listening on another device.
    private func resolvedStartPosition(for audiobook: Audiobook) -> Int {
        let local = api?.accountKey.flatMap { progressStore.localProgress(account: $0, audiobookId: audiobook.id) }
        // Builds before 1.0.1 kept only an untimed "last played" position.
        let lastId = UserDefaults.standard.integer(forKey: Self.lastAudiobookIdKey)
        let untimed = lastId == audiobook.id ? UserDefaults.standard.integer(forKey: Self.lastPositionKey) : nil
        return ProgressReconciler.resolve(
            serverPosition: audiobook.progress?.position,
            serverUpdatedAt: audiobook.progress?.updatedAt,
            local: local,
            untimedLocal: untimed
        )
    }

    /// Restore last played audiobook on app launch. Call after configure(api:).
    func restoreLastPlayed() async {
        // Called from the phone UI and from CarPlay (whichever comes up
        // first; with the phone locked, the SwiftUI scene may never appear).
        guard !didStartRestore else { return }
        didStartRestore = true
        let audiobookId = UserDefaults.standard.integer(forKey: Self.lastAudiobookIdKey)
        guard audiobookId > 0, let api = api else { return }

        // A downloaded book is restored from its saved metadata at once, so
        // the mini player, lock screen and CarPlay have it without waiting on
        // the server (which, on a slow link, could take a minute to answer).
        if let cached = DownloadManager.shared.cachedMeta[audiobookId]?.toAudiobook(),
           currentAudiobook == nil, player == nil {
            currentAudiobook = cached
            let local = api.accountKey.flatMap { progressStore.localProgress(account: $0, audiobookId: audiobookId) }
            let saved = UserDefaults.standard.integer(forKey: Self.lastPositionKey)
            position = TimeInterval(local?.position ?? max(saved, cached.progress?.position ?? 0))
            if let dur = cached.duration { duration = TimeInterval(dur) }
            updateCurrentChapter()
        }

        let audiobook: Audiobook
        let fetchedFromServer: Bool
        do {
            audiobook = try await Deadline.run(seconds: 15) { try await api.getAudiobook(id: audiobookId) }
            fetchedFromServer = true
        } catch {
            // Offline cold start: a downloaded book can still be restored from
            // its cached metadata, so the mini player and lock screen work.
            guard let cached = DownloadManager.shared.cachedMeta[audiobookId]?.toAudiobook() else {
                print("Failed to restore last played: \(error)")
                return
            }
            audiobook = cached
            fetchedFromServer = false
        }

        // Something else may have started playing while we waited.
        guard currentAudiobook == nil || currentAudiobook?.id == audiobookId, player == nil else { return }

        currentAudiobook = audiobook
        if fetchedFromServer {
            position = TimeInterval(resolvedStartPosition(for: audiobook))
        } else {
            // Cached metadata has no server timestamp; this device's saved
            // position is the best we have.
            let local = api.accountKey.flatMap { progressStore.localProgress(account: $0, audiobookId: audiobookId) }
            let saved = UserDefaults.standard.integer(forKey: Self.lastPositionKey)
            position = TimeInterval(local?.position ?? max(saved, audiobook.progress?.position ?? 0))
        }
        if let dur = audiobook.duration {
            duration = TimeInterval(dur)
        }
        updateCurrentChapter()

        // Load chapters
        guard fetchedFromServer else { return }
        if let chapters = try? await api.getChapters(audiobookId: audiobookId),
           currentAudiobook?.id == audiobookId {
            currentAudiobook = audiobook.withChapters(chapters)
            updateCurrentChapter()
        }
    }

    // MARK: - Private Methods

    private func startTimeObserver() {
        stopTimeObserver()
        let currentItem = playerItem
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Callback queue is explicitly .main, so it's safe to assume main-actor isolation.
            MainActor.assumeIsolated {
                guard let self = self, self.playerItem === currentItem else { return }
                self.position = time.seconds
                self.updateCurrentChapter()
                self.checkProgressSync()
                // Save to UserDefaults and refresh Now Playing info every ~5 seconds
                let currentPos = Int(time.seconds)
                if abs(currentPos - self.lastSavePosition) >= 5 {
                    self.savePlaybackState()
                    self.updateNowPlayingInfo()
                    self.lastSavePosition = currentPos
                }
            }
        }
    }

    private func stopTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func updateCurrentChapter() {
        guard let chapters = currentAudiobook?.chapters else { return }
        let previousChapter = currentChapter
        currentChapter = chapters.last { chapter in
            position >= chapter.startTime
        }
        // End-of-chapter sleep: pause when chapter changes
        if sleepAtEndOfChapter,
           let prev = previousChapter,
           let curr = currentChapter,
           prev.id != curr.id {
            pause()
            cancelSleepTimer()
        }
    }

    private func checkProgressSync() {
        let currentPosition = Int(position)
        if abs(currentPosition - lastSyncPosition) >= syncThreshold {
            syncProgressToServer()
            lastSyncPosition = currentPosition
        }
    }

    private func syncProgressToServer() {
        guard let audiobook = currentAudiobook, let api = api else { return }
        // Capture the account now: if this request fails after a logout, the
        // retry entry must belong to the account that made it, never to
        // whoever signs in next.
        guard let account = api.accountKey else { return }
        let pos = Int(position)
        let state = isPlaying ? "playing" : "paused"
        let store = progressStore

        Task {
            do {
                try await api.updateProgress(audiobookId: audiobook.id, position: pos, state: state)
                // Clear any pending sync for this book on success
                store.removePending(account: account, audiobookId: audiobook.id)
            } catch {
                // Queue for later retry
                store.savePending(account: account, audiobookId: audiobook.id, position: pos)
                print("Failed to sync progress (queued for retry): \(error)")
            }
        }
    }

    /// Send the current position and wait for it (bounded), for logout: the
    /// request has to go out while the session still exists.
    private func syncProgressNow(timeout: TimeInterval = 5) async {
        guard let audiobook = currentAudiobook, let api = api, api.accountKey != nil else { return }
        let pos = Int(position)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await api.updateProgress(audiobookId: audiobook.id, position: pos, state: "stopped")
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Pending Sync Queue

    /// Flush any progress updates that failed to sync while offline, for the
    /// signed-in account only.
    ///
    /// Each is sent with `isReplay`, so the server applies it only if it moves
    /// the position forward: listening done on another device since must not
    /// be erased by a phone reconnecting with an hours-old position.
    /// Entries are synced sequentially in a single task so the queue's
    /// read-modify-write updates never interleave and resurrect removed entries.
    func syncPendingProgress() {
        guard let api = api, let account = api.accountKey else { return }
        progressStore.migrateLegacyPending(to: account)
        let pending = progressStore.pending(account: account)
        guard !pending.isEmpty else { return }
        let store = progressStore

        Task {
            for (audiobookId, position) in pending {
                // Logged out (or switched account) mid-flush: stop.
                guard api.accountKey == account else { return }
                do {
                    try await api.updateProgress(audiobookId: audiobookId, position: position, state: "paused", isReplay: true)
                    store.removePending(account: account, audiobookId: audiobookId)
                    print("Synced pending progress for audiobook \(audiobookId) at \(position)s")
                } catch let error as APIError {
                    // Distinguish "cannot reach the server yet" from "the server
                    // answered, and the answer will never change".
                    //
                    // 404/410 mean the book is gone, so the entry can never
                    // succeed; drop it rather than retry it forever (a book
                    // removed and re-added under a new id once kept the phone
                    // posting to the dead id indefinitely). Anything else
                    // (including 401, which the API layer refreshes) stays
                    // queued for the next attempt.
                    if case let .httpError(statusCode, _) = error, statusCode == 404 || statusCode == 410 {
                        store.removePending(account: account, audiobookId: audiobookId)
                        print("Dropped pending progress for audiobook \(audiobookId): server returned \(statusCode)")
                    }
                } catch {
                    // Still offline — will retry next time
                }
            }
        }
    }

    // MARK: - Logout

    /// Everything playback-related that must happen before the session is
    /// cleared: send the final position while the token still works, stop
    /// without queuing another sync, and forget this account's queued and
    /// saved progress so nothing replays into the next account.
    func prepareForLogout() async {
        player?.pause()
        isPlaying = false
        await syncProgressNow()
        let account = api?.accountKey
        stop(syncProgress: false)
        if let account {
            progressStore.clear(account: account)
            HomeFeedStore.shared.clear(account: account)
        }
        hlsUnsupportedBookIds = []
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook else { return }

        let showChapterProgress = UserDefaults.standard.bool(forKey: "showChapterProgress")

        var info = [String: Any]()
        info[MPMediaItemPropertyArtist] = audiobook.author ?? "Unknown Author"
        info[MPMediaItemPropertyAlbumTitle] = audiobook.series
        // While waiting for audio the clock must not run on; the album line
        // (shown under the title in CarPlay) says why nothing is heard yet.
        let waiting = isPlaying && isBuffering
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying && !waiting ? playbackSpeed : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackSpeed
        if waiting {
            info[MPMediaItemPropertyAlbumTitle] = "Buffering…"
        }

        if showChapterProgress, let chapter = currentChapter {
            // Chapter-scoped progress: show chapter title, duration, and position within chapter
            let chapterStart = chapter.startTime
            let chapterDuration = chapter.duration ?? (duration - chapterStart)
            let chapterPosition = max(0, position - chapterStart)

            info[MPMediaItemPropertyTitle] = chapter.title ?? audiobook.title
            info[MPMediaItemPropertyPlaybackDuration] = chapterDuration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = chapterPosition

            if let chapters = audiobook.chapters {
                info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
                if let idx = chapters.firstIndex(where: { $0.id == chapter.id }) {
                    info[MPNowPlayingInfoPropertyChapterNumber] = idx + 1
                }
            }
        } else {
            // Full book progress
            info[MPMediaItemPropertyTitle] = audiobook.title
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }

        if let coverURL = api?.coverURL(for: audiobook.id) {
            let cacheKey = coverURL.absoluteString

            // Check cache synchronously — set artwork immediately if available
            if let cached = ImageCache.shared.image(for: cacheKey) {
                let artwork = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
                info[MPMediaItemPropertyArtwork] = artwork
            } else if let artURL = api?.coverURL(for: audiobook.id, width: CoverURL.artworkWidth) {
                // Cache miss: fetch a server-resized copy (an original can be
                // megabytes, competing with the audio on a slow link), once --
                // this runs every few seconds while playing.
                let artKey = artURL.absoluteString
                if let cached = ImageCache.shared.image(for: artKey) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
                } else if artworkFetchKey != artKey {
                    artworkFetchKey = artKey
                    var coverRequest = URLRequest(url: artURL, timeoutInterval: 30)
                    for (field, value) in (api?.authHeaders ?? [:]) {
                        coverRequest.setValue(value, forHTTPHeaderField: field)
                    }
                    let bookId = audiobook.id
                    Task {
                        defer { if self.artworkFetchKey == artKey { self.artworkFetchKey = nil } }
                        do {
                            let (data, response) = try await URLSession.shared.data(for: coverRequest)
                            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                                  let image = UIImage(data: data) else { return }
                            ImageCache.shared.setImage(image, for: artKey)
                            guard self.currentAudiobook?.id == bookId else { return }
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        } catch {
                            print("Failed to load cover art: \(error)")
                        }
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Remote command handlers are nonisolated entry points — hop onto the
        // main actor before touching player state.
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        let skipForward = UserDefaults.standard.integer(forKey: "skipForwardSeconds")
        let skipBackward = UserDefaults.standard.integer(forKey: "skipBackwardSeconds")
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForward > 0 ? skipForward : 30)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            let seconds = UserDefaults.standard.integer(forKey: "skipForwardSeconds")
            Task { @MainActor in
                self?.skipForward(seconds: TimeInterval(seconds > 0 ? seconds : 30))
            }
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackward > 0 ? skipBackward : 15)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            let seconds = UserDefaults.standard.integer(forKey: "skipBackwardSeconds")
            Task { @MainActor in
                self?.skipBackward(seconds: TimeInterval(seconds > 0 ? seconds : 15))
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let positionTime = event.positionTime
            Task { @MainActor in
                guard let self = self else { return }
                let showChapterProgress = UserDefaults.standard.bool(forKey: "showChapterProgress")
                if showChapterProgress, let chapter = self.currentChapter {
                    // Scrubber position is chapter-relative; convert to global
                    await self.seek(to: chapter.startTime + positionTime)
                } else {
                    await self.seek(to: positionTime)
                }
            }
            return .success
        }
    }

    // MARK: - Interruption Handling

    private var wasPlayingBeforeInterruption = false

    private func setupInterruptionHandling() {
        // All observers are delivered on the explicit .main queue, so it's safe
        // to assume main-actor isolation inside the handlers.
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleInterruption(notification: notification)
            }
        })
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleRouteChange(notification: notification)
            }
        })
        notificationTokens.add(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let endedItem = notification.object as AnyObject?
            MainActor.assumeIsolated {
                // Only our own current item; other AVPlayerItems (previews,
                // a replaced item finishing late) must not finish the book.
                guard let self, endedItem === self.playerItem else { return }
                self.handlePlaybackEnd()
            }
        })
    }

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            player?.pause()
            isPlaying = false
            syncProgressToServer()
            savePlaybackState()
            updateNowPlayingInfo()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let wasPlaying = wasPlayingBeforeInterruption
            wasPlayingBeforeInterruption = false
            if InterruptionPolicy.shouldResume(
                systemSaysShouldResume: options.contains(.shouldResume),
                wasPlaying: wasPlaying
            ) {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to reactivate audio session after interruption: \(error)")
                }
                player?.play()
                player?.rate = playbackSpeed
                isPlaying = true
                updateNowPlayingInfo()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Device disconnected (CarPlay off, headphones unplugged, AirPlay off).
            // Pause, and stay paused until the user says otherwise.
            player?.pause()
            isPlaying = false
            syncProgressToServer()
            savePlaybackState()
            updateNowPlayingInfo()
        case .newDeviceAvailable:
            // New device connected (CarPlay, Bluetooth, etc.)
            // Re-activate session but don't auto-resume — let user press play
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to reactivate audio session on route change: \(error)")
            }
            updateNowPlayingInfo()
        case .override, .routeConfigurationChange:
            // Never resume here. This used to restart playback when headphones
            // had been unplugged earlier, so an unrelated reconfiguration
            // (another app's category change, the AirPlay picker, CarPlay
            // negotiation) played the book out of the phone speaker. Playing
            // audio continues by itself; paused audio waits for the user.
            break
        default:
            break
        }
    }

    private func handlePlaybackEnd() {
        guard let audiobook = currentAudiobook, let api = api else { return }
        isPlaying = false
        updateNowPlayingInfo()
        savePlaybackState()

        let known = PlaybackCompletionPolicy.knownDuration(
            bookDuration: audiobook.duration,
            chapters: audiobook.chapters
        )
        guard PlaybackCompletionPolicy.isGenuineEnd(position: position, knownDuration: known) else {
            // The audio stopped well before the book's known end: part 1 of an
            // unmerged multi-file book, or a truncated file. Marking it
            // finished would reset it to 0 and queue the next in the series.
            // Keep the real position instead and say what happened.
            syncProgressToServer()
            if isPlayingLocalFile {
                DownloadManager.shared.invalidateDownload(
                    audiobookId: audiobook.id,
                    reason: "The downloaded file ended early. Download it again."
                )
                playbackError = "The downloaded file ended early, so it was removed. Play again to stream, or download it again."
            } else {
                playbackError = "Playback stopped before the end of the book. The server may not have the whole book in one file."
            }
            return
        }

        Task {
            do {
                try await api.markFinished(audiobookId: audiobook.id)
                print("Marked audiobook \(audiobook.id) as finished")
            } catch {
                print("Failed to mark audiobook as finished: \(error)")
            }
        }
    }

    /// Call when the app returns to foreground to ensure audio session is still valid
    func handleAppDidBecomeActive() {
        // Flush any progress that failed to sync while offline
        syncPendingProgress()

        guard currentAudiobook != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session on foreground: \(error)")
        }
    }

    // No deinit: notification observers are removed by NotificationTokenBag's own
    // deinit, so this @MainActor class never needs to touch isolated state there.
}

