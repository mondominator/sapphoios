import Foundation
import GoogleCast

@Observable
class CastManager: NSObject {
    static let shared = CastManager()

    var isCastAvailable: Bool = false
    var isCasting: Bool = false
    var castDeviceName: String?
    var castPosition: TimeInterval = 0

    private var sessionManager: GCKSessionManager?
    private var remoteMediaClient: GCKRemoteMediaClient?
    private var currentAudiobook: Audiobook?
    private var api: SapphoAPI?

    override init() {
        super.init()
        sessionManager = GCKCastContext.sharedInstance().sessionManager
        sessionManager?.add(self)

        // Check initial state
        if let session = sessionManager?.currentCastSession {
            isCasting = true
            castDeviceName = session.device.friendlyName
            remoteMediaClient = session.remoteMediaClient
            remoteMediaClient?.add(self)
        }
    }

    func configure(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Cast Controls

    func castAudiobook(_ audiobook: Audiobook, position: TimeInterval = 0) {
        guard let session = sessionManager?.currentCastSession,
              let streamURL = api?.streamURL(for: audiobook.id) else {
            return
        }

        currentAudiobook = audiobook
        remoteMediaClient = session.remoteMediaClient

        // Build metadata
        let metadata = GCKMediaMetadata(metadataType: .audioBookChapter)
        metadata.setString(audiobook.title, forKey: kGCKMetadataKeyTitle)
        metadata.setString(audiobook.author ?? "", forKey: kGCKMetadataKeyArtist)

        if let series = audiobook.series {
            metadata.setString(series, forKey: kGCKMetadataKeyAlbumTitle)
        }

        // Add cover image
        if let coverURL = api?.coverURL(for: audiobook.id) {
            metadata.addImage(GCKImage(url: coverURL, width: 480, height: 480))
        }

        // Build media info
        let builder = GCKMediaInformationBuilder(contentURL: streamURL)
        builder.streamType = .buffered
        builder.contentType = "audio/mp4"
        builder.metadata = metadata

        if let duration = audiobook.duration {
            builder.streamDuration = TimeInterval(duration)
        }

        let mediaInfo = builder.build()

        // Load with options
        let options = GCKMediaLoadOptions()
        options.playPosition = position
        options.autoplay = true

        remoteMediaClient?.loadMedia(mediaInfo, with: options)
        remoteMediaClient?.add(self)
    }

    func play() {
        remoteMediaClient?.play()
    }

    func pause() {
        remoteMediaClient?.pause()
    }

    func stop() {
        remoteMediaClient?.stop()
        currentAudiobook = nil
    }

    func seek(to position: TimeInterval) {
        let options = GCKMediaSeekOptions()
        options.interval = position
        remoteMediaClient?.seek(with: options)
    }

    func setPlaybackRate(_ rate: Float) {
        remoteMediaClient?.setPlaybackRate(rate)
    }

    func endSession() {
        sessionManager?.endSession()
    }
}

// MARK: - GCKSessionManagerListener
extension CastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        isCasting = true
        castDeviceName = session.device.friendlyName
        remoteMediaClient = session.remoteMediaClient
        remoteMediaClient?.add(self)
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        isCasting = false
        castDeviceName = nil
        remoteMediaClient = nil
        currentAudiobook = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        isCasting = true
        castDeviceName = session.device.friendlyName
        remoteMediaClient = session.remoteMediaClient
        remoteMediaClient?.add(self)
    }
}

// MARK: - GCKRemoteMediaClientListener
extension CastManager: GCKRemoteMediaClientListener {
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        if let status = mediaStatus {
            castPosition = status.streamPosition
        }
    }
}
