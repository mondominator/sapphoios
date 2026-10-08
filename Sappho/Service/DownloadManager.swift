import Foundation
import AVFoundation

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(localURL: URL)
    case failed(message: String)

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded):
            return true
        case (.downloading(let p1), .downloading(let p2)):
            return p1 == p2
        case (.downloaded(let u1), .downloaded(let u2)):
            return u1 == u2
        case (.failed(let m1), .failed(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

/// Lightweight metadata cached locally so downloaded books can be displayed offline.
struct DownloadedBookMeta: Codable {
    let id: Int
    let title: String
    let author: String?
    let narrator: String?
    let series: String?
    let seriesPosition: Float?
    let duration: Int?
    let genre: String?
    let coverImage: String?
    var lastPosition: Int?
    var completed: Int?
    var chapters: [CachedChapter]?
    /// The server's `file_size` when this download was made. Compared with the
    /// current value to detect a replaced or merged file (nil for downloads
    /// made before it was recorded).
    var serverFileSize: Int64?
    /// The stream's ETag ("size-mtime") and the byte count actually saved.
    var etag: String?
    var downloadedBytes: Int64?
    /// The linked server a remote book comes from (nil for local books and
    /// for downloads made before it was recorded), so the source tag still
    /// shows offline.
    var source: BookSource?

    init(from audiobook: Audiobook) {
        self.id = audiobook.id
        self.title = audiobook.title
        self.author = audiobook.author
        self.narrator = audiobook.narrator
        self.series = audiobook.series
        self.seriesPosition = audiobook.seriesPosition
        self.duration = audiobook.duration
        self.genre = audiobook.genre
        self.coverImage = audiobook.coverImage
        self.lastPosition = audiobook.progress?.position
        self.completed = audiobook.progress?.completed
        self.chapters = audiobook.chapters?.map { CachedChapter(from: $0) }
        self.serverFileSize = audiobook.fileSize
        self.source = audiobook.source
    }

    func toAudiobook() -> Audiobook {
        let progress: Progress? = if let pos = lastPosition, pos > 0 {
            Progress(position: pos, completed: completed ?? 0)
        } else {
            nil
        }
        return Audiobook(
            id: id,
            title: title,
            author: author,
            narrator: narrator,
            series: series,
            seriesPosition: seriesPosition,
            duration: duration,
            genre: genre,
            coverImage: coverImage,
            fileCount: 1,
            createdAt: "",
            progress: progress,
            chapters: chapters?.map { $0.toChapter() },
            source: source
        )
    }
}

/// Minimal chapter data for offline cache.
struct CachedChapter: Codable {
    let id: Int
    let audiobookId: Int
    let chapterNumber: Int
    let startTime: Double
    let duration: Double?
    let title: String?

    init(from chapter: Chapter) {
        self.id = chapter.id
        self.audiobookId = chapter.audiobookId
        self.chapterNumber = chapter.chapterNumber
        self.startTime = chapter.startTime
        self.duration = chapter.duration
        self.title = chapter.title
    }

    func toChapter() -> Chapter {
        Chapter(id: id, audiobookId: audiobookId, chapterNumber: chapterNumber, startTime: startTime, duration: duration, title: title)
    }
}

// MARK: - DownloadManager

/// Manages audiobook downloads with background URL session support.
///
/// This class uses the singleton pattern (`DownloadManager.shared`) because:
/// 1. It must handle background URL session delegate callbacks from the system
/// 2. `AppDelegate` must forward background session events to the same instance
/// 3. `URLSession` background sessions require a single delegate for the app lifetime
@Observable
class DownloadManager: NSObject {
    static let shared = DownloadManager()

    static let sessionIdentifier = "com.sappho.audiobooks.download"

    var downloads: [Int: DownloadState] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    /// Cached metadata for downloaded books — available offline.
    private(set) var cachedMeta: [Int: DownloadedBookMeta] = [:]

    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    /// Metadata for downloads in flight, persisted at enqueue time so a
    /// transfer that completes after the app was killed (the background
    /// session relaunches us) still gets its title, chapters and server size.
    /// It used to live in memory only, so such books were saved without
    /// metadata and never appeared in the offline list.
    private var pendingMeta: [Int: DownloadedBookMeta] = [:]
    /// Resume data captured when a download is cancelled, keyed by audiobook id.
    /// Consumed by the next download(audiobook:) call for the same book so the
    /// transfer picks up where it left off instead of restarting.
    private var resumeDataByBook: [Int: Data] = [:]
    private var api: SapphoAPI?
    private var _session: URLSession?

    private var session: URLSession {
        if let existing = _session {
            return existing
        }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _session = newSession
        return newSession
    }

    /// Downloads directory, created (and excluded from backup) exactly once.
    /// Stored rather than computed because this is on hot paths — localURL(for:)
    /// runs twice per play() — and the old computed var hit the file system with
    /// createDirectory + setResourceValues on every access.
    private let downloadsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var downloads = appSupport.appendingPathComponent("Downloads", isDirectory: true)

        if !FileManager.default.fileExists(atPath: downloads.path) {
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? downloads.setResourceValues(values)

        return downloads
    }()

    private var metadataURL: URL {
        downloadsDirectory.appendingPathComponent("metadata.json")
    }

    private var pendingMetadataURL: URL {
        downloadsDirectory.appendingPathComponent("pending.json")
    }

    override init() {
        super.init()
        loadMetadata()
        loadDownloadedFiles()
    }

    func configure(api: SapphoAPI) {
        self.api = api
        reattachSession()
    }

    /// Recreate the background session at launch (and when iOS relaunches us
    /// for background-session events) so transfers that finished or progressed
    /// while the app was not running are delivered to a delegate. The session
    /// used to be created lazily by the first download() call, so completions
    /// that arrived after a relaunch were dropped and the completion handler
    /// iOS passed to the app delegate was never called.
    func reattachSession() {
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for case let task as URLSessionDownloadTask in tasks {
                    guard let idString = task.taskDescription, let id = Int(idString) else { continue }
                    guard task.state == .running || task.state == .suspended else { continue }
                    self.downloadTasks[id] = task
                    if case .downloaded = self.downloads[id] { continue }
                    let expected = task.countOfBytesExpectedToReceive
                    let progress = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
                    self.downloads[id] = .downloading(progress: progress)
                }
            }
        }
    }

    // MARK: - Public Methods

    func download(audiobook: Audiobook) {
        guard let url = api?.streamURL(for: audiobook.id) else {
            downloads[audiobook.id] = .failed(message: "Could not create download URL")
            return
        }

        // Persist metadata now, not on completion: see pendingMeta.
        pendingMeta[audiobook.id] = DownloadedBookMeta(from: audiobook)
        savePendingMetadata()
        downloads[audiobook.id] = .downloading(progress: 0)

        Task { @MainActor in
            // The token baked into the request is used by nsurlsessiond, which
            // cannot refresh it. Make sure it is fresh before handing it over,
            // or an expired token downloads a 401 body.
            if let api = self.api {
                await api.ensureFreshToken()
            }
            self.startTask(for: audiobook.id, url: url)
        }
    }

    private func startTask(for audiobookId: Int, url: URL) {
        // A cancel during the token check wins.
        guard case .downloading = downloads[audiobookId] else { return }

        let task: URLSessionDownloadTask
        if let resumeData = resumeDataByBook.removeValue(forKey: audiobookId) {
            // Resume a previously cancelled download instead of restarting.
            // If the embedded request's auth token has since expired, the task
            // fails and a subsequent retry falls back to a fresh download.
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            for (field, value) in (api?.authHeaders ?? [:]) {
                request.setValue(value, forHTTPHeaderField: field)
            }
            task = session.downloadTask(with: request)
        }
        task.taskDescription = String(audiobookId)
        downloadTasks[audiobookId] = task
        task.resume()
    }

    func cancelDownload(audiobookId: Int) {
        // Cancel while producing resume data so a retried download can pick up
        // where it left off rather than starting over.
        downloadTasks[audiobookId]?.cancel { [weak self] resumeData in
            guard let resumeData else { return }
            DispatchQueue.main.async {
                self?.resumeDataByBook[audiobookId] = resumeData
            }
        }
        downloadTasks.removeValue(forKey: audiobookId)
        removePendingMeta(audiobookId)
        downloads[audiobookId] = .notDownloaded
    }

    func removeDownload(audiobookId: Int) {
        if let url = localURL(for: audiobookId) {
            try? FileManager.default.removeItem(at: url)
        }
        downloads[audiobookId] = .notDownloaded
        cachedMeta.removeValue(forKey: audiobookId)
        resumeDataByBook.removeValue(forKey: audiobookId)
        saveMetadata()
    }

    /// Delete a downloaded file that turned out to be wrong (truncated, an
    /// error body, ended early during playback) and say why, so the book shows
    /// as failed rather than Downloaded and playback falls back to the stream.
    func invalidateDownload(audiobookId: Int, reason: String) {
        removeDownload(audiobookId: audiobookId)
        downloads[audiobookId] = .failed(message: reason)
        print("Removed invalid download for audiobook \(audiobookId): \(reason)")
    }

    func localURL(for audiobookId: Int) -> URL? {
        let fileURL = downloadsDirectory.appendingPathComponent("\(audiobookId).m4b")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    func isDownloaded(_ audiobookId: Int) -> Bool {
        if case .downloaded = downloads[audiobookId] {
            return true
        }
        return false
    }

    /// Update the cached position for a downloaded book.
    func updatePosition(audiobookId: Int, position: Int) {
        guard var meta = cachedMeta[audiobookId] else { return }
        meta.lastPosition = position
        cachedMeta[audiobookId] = meta
        saveMetadata()
    }

    /// Cache chapters for a downloaded book (called when chapters are loaded from API).
    func cacheChapters(audiobookId: Int, chapters: [Chapter]) {
        guard var meta = cachedMeta[audiobookId] else { return }
        guard meta.chapters == nil || meta.chapters?.isEmpty == true else { return }
        meta.chapters = chapters.map { CachedChapter(from: $0) }
        cachedMeta[audiobookId] = meta
        saveMetadata()
    }

    /// Returns Audiobook objects for all downloaded books using cached metadata.
    func downloadedAudiobooks() -> [Audiobook] {
        downloads.compactMap { (id, state) -> Audiobook? in
            guard case .downloaded = state else { return nil }
            return cachedMeta[id]?.toAudiobook()
        }
    }

    func totalDownloadSize() -> Int64 {
        var total: Int64 = 0
        let fileManager = FileManager.default

        if let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files where file.pathExtension != "json" {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }

        return total
    }

    func clearAllDownloads() {
        let fileManager = FileManager.default

        if let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension != "json" {
                try? fileManager.removeItem(at: file)
            }
        }

        downloads.removeAll()
        cachedMeta.removeAll()
        resumeDataByBook.removeAll()
        saveMetadata()
        loadDownloadedFiles()
    }

    // MARK: - Integrity and freshness

    /// Check every downloaded file once per launch:
    /// 1. drop files that are not audio or are too small (error bodies saved
    ///    by builds that did not check the HTTP status), and files whose audio
    ///    is clearly shorter than the book (partial or part-1 downloads);
    /// 2. when online, re-download books whose file changed on the server
    ///    (replaced, or a multi-file book merged into one m4b).
    @MainActor
    func auditDownloads(online: Bool) async {
        for (id, state) in downloads {
            guard case .downloaded(let fileURL) = state else { continue }
            let size = Self.fileSize(at: fileURL)
            let verdict = DownloadValidator.validateFile(
                size: size,
                expectedLength: nil,
                leadingBytes: Self.leadingBytes(of: fileURL)
            )
            if case .invalid(let reason) = verdict {
                invalidateDownload(audiobookId: id, reason: reason)
                continue
            }

            if let expected = cachedMeta[id]?.duration {
                let actual = await Self.audioDuration(of: fileURL)
                if case .invalid(let reason) = DownloadValidator.validateDuration(actual: actual, expected: TimeInterval(expected)) {
                    invalidateDownload(audiobookId: id, reason: reason)
                    continue
                }
            }

            guard online, let api else { continue }
            await refreshIfStale(audiobookId: id, localSize: size, api: api)
        }
    }

    @MainActor
    private func refreshIfStale(audiobookId: Int, localSize: Int64, api: SapphoAPI) async {
        let meta = cachedMeta[audiobookId]
        let book: Audiobook
        do {
            book = try await api.getAudiobook(id: audiobookId)
        } catch {
            return // offline or the book is gone; leave the file alone
        }

        var stale = false
        if book.fileSize != nil {
            stale = DownloadValidator.isStale(
                recordedServerSize: meta?.serverFileSize,
                localSize: localSize,
                currentServerSize: book.fileSize
            )
        } else if let info = try? await api.streamInfo(for: audiobookId) {
            if info.statusCode == 409 {
                stale = true // unmerged multi-file book: the local file is part 1 only
            } else if 200..<300 ~= info.statusCode {
                stale = DownloadValidator.isStale(
                    recordedETag: meta?.etag,
                    localSize: localSize,
                    streamETag: info.etag,
                    streamLength: info.contentLength
                )
            }
        }

        guard stale else { return }
        print("Server file changed for audiobook \(audiobookId); re-downloading")
        let chapters = meta?.chapters?.map { $0.toChapter() }
        removeDownload(audiobookId: audiobookId)
        download(audiobook: book.chapters == nil ? book.withChapters(chapters) : book)
    }

    /// Synchronous check with a book just fetched from the server (no extra
    /// request): if its `file_size` says the download is out of date, delete
    /// it and start a fresh download. Returns true when it was discarded.
    @discardableResult
    func discardIfStale(for book: Audiobook) -> Bool {
        guard let fileURL = localURL(for: book.id), book.fileSize != nil else { return false }
        let stale = DownloadValidator.isStale(
            recordedServerSize: cachedMeta[book.id]?.serverFileSize,
            localSize: Self.fileSize(at: fileURL),
            currentServerSize: book.fileSize
        )
        guard stale else { return false }
        let chapters = cachedMeta[book.id]?.chapters?.map { $0.toChapter() }
        removeDownload(audiobookId: book.id)
        download(audiobook: book.chapters == nil ? book.withChapters(chapters) : book)
        return true
    }

    static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func leadingBytes(of url: URL, count: Int = 16) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    static func audioDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    // MARK: - Metadata Persistence

    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(Array(cachedMeta.values))
            try data.write(to: metadataURL)
        } catch {
            print("Failed to save download metadata: \(error)")
        }
    }

    private func loadMetadata() {
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                let metas = try JSONDecoder().decode([DownloadedBookMeta].self, from: data)
                cachedMeta = Dictionary(metas.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            } catch {
                print("Failed to load download metadata: \(error)")
            }
        }
        if let data = try? Data(contentsOf: pendingMetadataURL),
           let metas = try? JSONDecoder().decode([DownloadedBookMeta].self, from: data) {
            pendingMeta = Dictionary(metas.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
    }

    private func savePendingMetadata() {
        if let data = try? JSONEncoder().encode(Array(pendingMeta.values)) {
            try? data.write(to: pendingMetadataURL)
        }
    }

    private func removePendingMeta(_ audiobookId: Int) {
        if pendingMeta.removeValue(forKey: audiobookId) != nil {
            savePendingMetadata()
        }
    }

    // MARK: - Private Methods

    private func loadDownloadedFiles() {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension != "json" {
            let filename = file.deletingPathExtension().lastPathComponent
            if let audiobookId = Int(filename) {
                downloads[audiobookId] = .downloaded(localURL: file)
            }
        }
    }

    /// Main-thread completion bookkeeping, split out so the delegate method
    /// (which must move the file synchronously) stays readable.
    private func finishDownload(audiobookId: Int, destination: URL, etag: String?, bytes: Int64) {
        downloads[audiobookId] = .downloaded(localURL: destination)
        downloadTasks.removeValue(forKey: audiobookId)

        var meta = pendingMeta[audiobookId] ?? cachedMeta[audiobookId]
        meta?.etag = etag
        meta?.downloadedBytes = bytes
        if let meta {
            cachedMeta[audiobookId] = meta
            saveMetadata()
        }
        removePendingMeta(audiobookId)
    }

    private func failDownload(audiobookId: Int, message: String) {
        downloads[audiobookId] = .failed(message: message)
        downloadTasks.removeValue(forKey: audiobookId)
        removePendingMeta(audiobookId)
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let audiobookIdString = downloadTask.taskDescription,
              let audiobookId = Int(audiobookIdString) else {
            return
        }

        // The temp file is deleted when this method returns, so validate and
        // move it here, synchronously.
        let http = downloadTask.response as? HTTPURLResponse
        let size = Self.fileSize(at: location)
        var verdict = DownloadValidator.validateResponse(statusCode: http?.statusCode)
        if verdict.isValid {
            // Content-Length is the whole file only for a 200; a resumed 206
            // reports the remaining range.
            let expected: Int64? = http?.statusCode == 200 && downloadTask.countOfBytesExpectedToReceive > 0
                ? downloadTask.countOfBytesExpectedToReceive : nil
            verdict = DownloadValidator.validateFile(
                size: size,
                expectedLength: expected,
                leadingBytes: Self.leadingBytes(of: location)
            )
        }

        if case .invalid(var reason) = verdict {
            // Surface the server's own explanation when it sent one.
            if size < 4096, let data = try? Data(contentsOf: location),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverMessage = (object["error"] ?? object["message"]) as? String {
                reason += ": \(serverMessage)"
            }
            try? FileManager.default.removeItem(at: location)
            DispatchQueue.main.async {
                self.failDownload(audiobookId: audiobookId, message: reason)
            }
            return
        }

        let destinationURL = downloadsDirectory.appendingPathComponent("\(audiobookId).m4b")
        let etag = http?.value(forHTTPHeaderField: "ETag")

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.finishDownload(audiobookId: audiobookId, destination: destinationURL, etag: etag, bytes: size)
            }
        } catch {
            DispatchQueue.main.async {
                self.failDownload(audiobookId: audiobookId, message: error.localizedDescription)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let audiobookIdString = downloadTask.taskDescription,
              let audiobookId = Int(audiobookIdString) else {
            return
        }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = -1
        }

        DispatchQueue.main.async {
            // Don't resurrect a download the user cancelled meanwhile.
            guard self.downloadTasks[audiobookId] != nil else { return }
            self.downloads[audiobookId] = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error,
              let downloadTask = task as? URLSessionDownloadTask,
              let audiobookIdString = downloadTask.taskDescription,
              let audiobookId = Int(audiobookIdString) else {
            return
        }

        // User-initiated cancellation (cancelDownload) already reset the state to
        // .notDownloaded — don't overwrite it with .failed.
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }

        DispatchQueue.main.async {
            self.failDownload(audiobookId: audiobookId, message: error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
