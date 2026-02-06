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

    // MARK: - Initialization

    override init() {
        super.init()
        setupRemoteCommands()
        setupInterruptionHandling()
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

        // Load chapters if available
        if audiobook.chapters == nil {
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
    }

    func resume() {
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

    // MARK: - Private Methods

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.position = time.seconds
            self.updateCurrentChapter()
            self.checkProgressSync()
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

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
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

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
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
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
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

