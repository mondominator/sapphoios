import Foundation
import AVFoundation
import MediaPlayer

@Observable
class AudioPlayerService: NSObject {
    // MARK: - Public State
    var currentAudiobook: Audiobook?
    var currentChapter: Chapter?
    var isPlaying: Bool = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackSpeed: Float = 1.0
    var isBuffering: Bool = false
    var sleepTimerRemaining: TimeInterval?
    var showFullPlayer: Bool = false

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var isObservingPlayerItem = false
    private var interruptionObserver: Any?
    private var routeChangeObserver: Any?

    private var api: SapphoAPI?
    private var lastSyncPosition: Int = 0
    private let syncThreshold: Int = 20 // Sync every 20 seconds (matching Android)
    private var lastSavePosition: Int = 0

    // Persistence keys
    private static let lastAudiobookIdKey = "lastPlayedAudiobookId"
    private static let lastPositionKey = "lastPlayedPosition"
    private static let pendingSyncKey = "pendingProgressSync"

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        setupInterruptionHandling()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func configure(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Playback Controls

    func play(audiobook: Audiobook, startPosition: TimeInterval? = nil) async {
        // Stop current playback
        stop()

        currentAudiobook = audiobook

        // Check for offline download first
        let url: URL?
        if let localURL = DownloadManager.shared.localURL(for: audiobook.id) {
            url = localURL
        } else {
            url = api?.streamURL(for: audiobook.id)
        }

        guard let streamURL = url else {
            print("Failed to get stream URL for audiobook \(audiobook.id)")
            return
        }

        // Create player item — use auth headers for remote streams
        let asset: AVURLAsset
        if DownloadManager.shared.localURL(for: audiobook.id) != nil {
            asset = AVURLAsset(url: streamURL)
        } else {
            let headers = api?.authHeaders ?? [:]
            asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        playerItem = AVPlayerItem(asset: asset)

        // Observe buffering state
        playerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
        isObservingPlayerItem = true

        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.rate = playbackSpeed

        // Get duration
        if let durationSeconds = audiobook.duration {
            duration = TimeInterval(durationSeconds)
        }

        // Seek to start position if provided
        let seekPosition = startPosition ?? TimeInterval(audiobook.progress?.position ?? 0)
        if seekPosition > 0 {
            await seek(to: seekPosition)
        }

        // Start playback
        player?.play()
        isPlaying = true

        // Start time observer
        startTimeObserver()

        // Update now playing info
        updateNowPlayingInfo()

        // Load chapters if not already loaded
        if audiobook.chapters == nil || audiobook.chapters?.isEmpty == true {
            Task {
                do {
                    let chapters = try await api?.getChapters(audiobookId: audiobook.id)
                    await MainActor.run {
                        self.currentAudiobook = audiobook.withChapters(chapters)
                        // Cache chapters for offline playback
                        if let chapters = chapters {
                            DownloadManager.shared.cacheChapters(audiobookId: audiobook.id, chapters: chapters)
                        }
                    }
                } catch {
                    print("Failed to load chapters: \(error)")
                }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        syncProgressToServer()
        savePlaybackState()
    }

    func resume() {
        // Re-activate audio session in case it was deactivated
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }

        // If player was destroyed (e.g. app was killed and restored), recreate it
        if player == nil, let audiobook = currentAudiobook {
            Task {
                await play(audiobook: audiobook, startPosition: position)
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

    func stop() {
        syncProgressToServer()

        player?.pause()
        stopTimeObserver()

        if isObservingPlayerItem {
            playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
            isObservingPlayerItem = false
        }

        player = nil
        playerItem = nil
        currentAudiobook = nil
        currentChapter = nil
        isPlaying = false
        position = 0
        duration = 0
        showFullPlayer = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        UserDefaults.standard.removeObject(forKey: Self.lastAudiobookIdKey)
        UserDefaults.standard.removeObject(forKey: Self.lastPositionKey)
    }

    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        await player?.seek(to: cmTime)
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

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTimerRemaining = TimeInterval(minutes * 60)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
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

        // Keep downloaded book metadata in sync
        DownloadManager.shared.updatePosition(audiobookId: audiobook.id, position: pos)
    }

    /// Restore last played audiobook on app launch. Call after configure(api:).
    func restoreLastPlayed() async {
        let audiobookId = UserDefaults.standard.integer(forKey: Self.lastAudiobookIdKey)
        guard audiobookId > 0, let api = api else { return }

        do {
            let audiobook = try await api.getAudiobook(id: audiobookId)
            await MainActor.run {
                self.currentAudiobook = audiobook
                // Use server progress if available, fall back to saved position
                if let serverPosition = audiobook.progress?.position, serverPosition > 0 {
                    self.position = TimeInterval(serverPosition)
                } else {
                    let savedPosition = UserDefaults.standard.integer(forKey: Self.lastPositionKey)
                    self.position = TimeInterval(savedPosition)
                }
                if let dur = audiobook.duration {
                    self.duration = TimeInterval(dur)
                }
            }
            // Load chapters
            if let chapters = try? await api.getChapters(audiobookId: audiobookId) {
                await MainActor.run {
                    self.currentAudiobook = audiobook.withChapters(chapters)
                    self.updateCurrentChapter()
                }
            }
        } catch {
            print("Failed to restore last played: \(error)")
        }
    }

    // MARK: - Private Methods

    private func startTimeObserver() {
        stopTimeObserver()
        let currentItem = playerItem
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.playerItem === currentItem else { return }
            self.position = time.seconds
            self.updateCurrentChapter()
            self.checkProgressSync()
            // Save to UserDefaults every ~5 seconds
            let currentPos = Int(time.seconds)
            if abs(currentPos - self.lastSavePosition) >= 5 {
                self.savePlaybackState()
                self.lastSavePosition = currentPos
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
        currentChapter = chapters.last { chapter in
            position >= chapter.startTime
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
        let pos = Int(position)
        let state = isPlaying ? "playing" : "paused"

        Task {
            do {
                try await api.updateProgress(audiobookId: audiobook.id, position: pos, state: state)
                // Clear any pending sync for this book on success
                removePendingSync(for: audiobook.id)
            } catch {
                // Queue for later retry
                savePendingSync(audiobookId: audiobook.id, position: pos)
                print("Failed to sync progress (queued for retry): \(error)")
            }
        }
    }

    // MARK: - Pending Sync Queue

    private func savePendingSync(audiobookId: Int, position: Int) {
        var pending = UserDefaults.standard.dictionary(forKey: Self.pendingSyncKey) as? [String: Int] ?? [:]
        pending[String(audiobookId)] = position
        UserDefaults.standard.set(pending, forKey: Self.pendingSyncKey)
    }

    private func removePendingSync(for audiobookId: Int) {
        var pending = UserDefaults.standard.dictionary(forKey: Self.pendingSyncKey) as? [String: Int] ?? [:]
        pending.removeValue(forKey: String(audiobookId))
        UserDefaults.standard.set(pending, forKey: Self.pendingSyncKey)
    }

    /// Flush any progress updates that failed to sync while offline.
    func syncPendingProgress() {
        guard let api = api else { return }
        let pending = UserDefaults.standard.dictionary(forKey: Self.pendingSyncKey) as? [String: Int] ?? [:]
        guard !pending.isEmpty else { return }

        for (idString, position) in pending {
            guard let audiobookId = Int(idString) else { continue }
            Task {
                do {
                    try await api.updateProgress(audiobookId: audiobookId, position: position, state: "paused")
                    removePendingSync(for: audiobookId)
                    print("Synced pending progress for audiobook \(audiobookId) at \(position)s")
                } catch {
                    // Still offline — will retry next time
                }
            }
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = audiobook.title
        info[MPMediaItemPropertyArtist] = audiobook.author ?? "Unknown Author"
        info[MPMediaItemPropertyAlbumTitle] = audiobook.series
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0

        // Load cover art asynchronously
        if let coverURL = api?.coverURL(for: audiobook.id) {
            Task {
                do {
                    var coverRequest = URLRequest(url: coverURL)
                    for (field, value) in (api?.authHeaders ?? [:]) {
                        coverRequest.setValue(value, forHTTPHeaderField: field)
                    }
                    let (data, _) = try await URLSession.shared.data(for: coverRequest)
                    if let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updatedInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    }
                } catch {
                    print("Failed to load cover art: \(error)")
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        let skipForward = UserDefaults.standard.integer(forKey: "skipForwardSeconds")
        let skipBackward = UserDefaults.standard.integer(forKey: "skipBackwardSeconds")
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForward > 0 ? skipForward : 30)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            let seconds = UserDefaults.standard.integer(forKey: "skipForwardSeconds")
            self?.skipForward(seconds: TimeInterval(seconds > 0 ? seconds : 30))
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackward > 0 ? skipBackward : 15)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            let seconds = UserDefaults.standard.integer(forKey: "skipBackwardSeconds")
            self?.skipBackward(seconds: TimeInterval(seconds > 0 ? seconds : 15))
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task {
                await self?.seek(to: event.positionTime)
            }
            return .success
        }
    }

    // MARK: - Interruption Handling

    private var wasPlayingBeforeInterruption = false

    private func setupInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification: notification)
        }
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
            pause()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) || wasPlayingBeforeInterruption {
                resume()
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

        // Pause when output device is disconnected (e.g. headphones unplugged)
        if reason == .oldDeviceUnavailable {
            pause()
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

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if keyPath == "playbackBufferEmpty" {
                self.isBuffering = true
            } else if keyPath == "playbackLikelyToKeepUp" {
                self.isBuffering = false
            }
        }
    }

    deinit {
        if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = routeChangeObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

