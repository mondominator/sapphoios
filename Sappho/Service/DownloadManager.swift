import Foundation

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
            chapters: chapters?.map { $0.toChapter() }
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

@Observable
class DownloadManager: NSObject {
    static let shared = DownloadManager()

    var downloads: [Int: DownloadState] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    /// Cached metadata for downloaded books — available offline.
    private(set) var cachedMeta: [Int: DownloadedBookMeta] = [:]

    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    private var pendingAudiobooks: [Int: Audiobook] = [:]
    private var api: SapphoAPI?
    private var _session: URLSession?

    private var session: URLSession {
        if let existing = _session {
            return existing
        }
        let config = URLSessionConfiguration.background(withIdentifier: "com.sappho.audiobooks.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _session = newSession
        return newSession
    }

    private var downloadsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloads = appSupport.appendingPathComponent("Downloads", isDirectory: true)

        if !FileManager.default.fileExists(atPath: downloads.path) {
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        }

        return downloads
    }

    private var metadataURL: URL {
        downloadsDirectory.appendingPathComponent("metadata.json")
    }

    override init() {
        super.init()
        loadMetadata()
        loadDownloadedFiles()
    }

    func configure(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Public Methods

    func download(audiobook: Audiobook) {
        guard let url = api?.streamURL(for: audiobook.id) else {
            downloads[audiobook.id] = .failed(message: "Could not create download URL")
            return
        }

        // Store audiobook so we can save metadata when download completes
        pendingAudiobooks[audiobook.id] = audiobook

        let task = session.downloadTask(with: url)
        task.taskDescription = String(audiobook.id)
        downloadTasks[audiobook.id] = task
        downloads[audiobook.id] = .downloading(progress: 0)
        task.resume()
    }

    func cancelDownload(audiobookId: Int) {
        downloadTasks[audiobookId]?.cancel()
        downloadTasks.removeValue(forKey: audiobookId)
        pendingAudiobooks.removeValue(forKey: audiobookId)
        downloads[audiobookId] = .notDownloaded
    }

    func removeDownload(audiobookId: Int) {
        if let url = localURL(for: audiobookId) {
            try? FileManager.default.removeItem(at: url)
        }
        downloads[audiobookId] = .notDownloaded
        cachedMeta.removeValue(forKey: audiobookId)
        saveMetadata()
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

    func downloadProgress(for audiobookId: Int) -> Double? {
        if case .downloading(let progress) = downloads[audiobookId] {
            return progress
        }
        return nil
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
        saveMetadata()
        loadDownloadedFiles()
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
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            let metas = try JSONDecoder().decode([DownloadedBookMeta].self, from: data)
            cachedMeta = Dictionary(uniqueKeysWithValues: metas.map { ($0.id, $0) })
        } catch {
            print("Failed to load download metadata: \(error)")
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
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let audiobookIdString = downloadTask.taskDescription,
              let audiobookId = Int(audiobookIdString) else {
            return
        }

        let destinationURL = downloadsDirectory.appendingPathComponent("\(audiobookId).m4b")

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.downloads[audiobookId] = .downloaded(localURL: destinationURL)
                self.downloadTasks.removeValue(forKey: audiobookId)

                // Save metadata for offline access
                if let audiobook = self.pendingAudiobooks.removeValue(forKey: audiobookId) {
                    self.cachedMeta[audiobookId] = DownloadedBookMeta(from: audiobook)
                    self.saveMetadata()
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.downloads[audiobookId] = .failed(message: error.localizedDescription)
                self.downloadTasks.removeValue(forKey: audiobookId)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let audiobookIdString = downloadTask.taskDescription,
              let audiobookId = Int(audiobookIdString) else {
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async {
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

        DispatchQueue.main.async {
            self.downloads[audiobookId] = .failed(message: error.localizedDescription)
            self.downloadTasks.removeValue(forKey: audiobookId)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
