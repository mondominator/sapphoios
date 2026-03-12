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

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var sleepTimer: Timer?

    private var api: SapphoAPI?
    private var lastSyncPosition: Int = 0
    private let syncThreshold: Int = 20 // Sync every 20 seconds (matching Android)
    private var lastSavePosition: Int = 0

    // Persistence keys
    private static let lastAudiobookIdKey = "lastPlayedAudiobookId"
    private static let lastPositionKey = "lastPlayedPosition"

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

        // Create player item
        let asset = AVURLAsset(url: streamURL)
        playerItem = AVPlayerItem(asset: asset)

        // Observe buffering state
        playerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)

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
                        self.currentAudiobook = Audiobook(
                            id: audiobook.id,
                            title: audiobook.title,
                            subtitle: audiobook.subtitle,
                            author: audiobook.author,
                            narrator: audiobook.narrator,
                            series: audiobook.series,
                            seriesPosition: audiobook.seriesPosition,
                            duration: audiobook.duration,
                            genre: audiobook.genre,
                            tags: audiobook.tags,
                            publishYear: audiobook.publishYear,
                            copyrightYear: audiobook.copyrightYear,
                            publisher: audiobook.publisher,
                            isbn: audiobook.isbn,
                            asin: audiobook.asin,
                            language: audiobook.language,
                            rating: audiobook.rating,
                            userRating: audiobook.userRating,
                            averageRating: audiobook.averageRating,
                            abridged: audiobook.abridged,
                            description: audiobook.description,
                            coverImage: audiobook.coverImage,
                            fileCount: audiobook.fileCount,
                            isMultiFile: audiobook.isMultiFile,
                            createdAt: audiobook.createdAt,
                            progress: audiobook.progress,
                            chapters: chapters,
                            isFavorite: audiobook.isFavorite
                        )
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

        playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")

        player = nil
        playerItem = nil
        currentAudiobook = nil
        currentChapter = nil
        isPlaying = false
        position = 0
        duration = 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

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
        UserDefaults.standard.set(audiobook.id, forKey: Self.lastAudiobookIdKey)
        UserDefaults.standard.set(Int(position), forKey: Self.lastPositionKey)
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
                    self.currentAudiobook = Audiobook(
                        id: audiobook.id,
                        title: audiobook.title,
                        subtitle: audiobook.subtitle,
                        author: audiobook.author,
                        narrator: audiobook.narrator,
                        series: audiobook.series,
                        seriesPosition: audiobook.seriesPosition,
                        duration: audiobook.duration,
                        genre: audiobook.genre,
                        tags: audiobook.tags,
                        publishYear: audiobook.publishYear,
                        copyrightYear: audiobook.copyrightYear,
                        publisher: audiobook.publisher,
                        isbn: audiobook.isbn,
                        asin: audiobook.asin,
                        language: audiobook.language,
                        rating: audiobook.rating,
                        userRating: audiobook.userRating,
                        averageRating: audiobook.averageRating,
                        abridged: audiobook.abridged,
                        description: audiobook.description,
                        coverImage: audiobook.coverImage,
                        fileCount: audiobook.fileCount,
                        isMultiFile: audiobook.isMultiFile,
                        createdAt: audiobook.createdAt,
                        progress: audiobook.progress,
                        chapters: chapters,
                        isFavorite: audiobook.isFavorite
                    )
                    self.updateCurrentChapter()
                }
            }
        } catch {
            print("Failed to restore last played: \(error)")
        }
    }

    // MARK: - Private Methods

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
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
            } catch {
                print("Failed to sync progress: \(error)")
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
                    let (data, _) = try await URLSession.shared.data(from: coverURL)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
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

    @objc private func handleRouteChange(notification: Notification) {
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
        guard currentAudiobook != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session on foreground: \(error)")
        }
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "playbackBufferEmpty" {
            isBuffering = true
        } else if keyPath == "playbackLikelyToKeepUp" {
            isBuffering = false
        }
    }
}

