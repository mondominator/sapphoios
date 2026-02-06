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

@Observable
class DownloadManager: NSObject {
    static let shared = DownloadManager()

    var downloads: [Int: DownloadState] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    private var api: SapphoAPI?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.sappho.audiobooks.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var downloadsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloads = appSupport.appendingPathComponent("Downloads", isDirectory: true)

        if !FileManager.default.fileExists(atPath: downloads.path) {
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        }

        return downloads
    }

    override init() {
        super.init()
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

        let task = session.downloadTask(with: url)
        task.taskDescription = String(audiobook.id)
        downloadTasks[audiobook.id] = task
        downloads[audiobook.id] = .downloading(progress: 0)
        task.resume()
    }

    func cancelDownload(audiobookId: Int) {
        downloadTasks[audiobookId]?.cancel()
        downloadTasks.removeValue(forKey: audiobookId)
        downloads[audiobookId] = .notDownloaded
    }

    func removeDownload(audiobookId: Int) {
        if let url = localURL(for: audiobookId) {
            try? FileManager.default.removeItem(at: url)
        }
        downloads[audiobookId] = .notDownloaded
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

    func totalDownloadSize() -> Int64 {
        var total: Int64 = 0
        let fileManager = FileManager.default

        if let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
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
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }

        downloads.removeAll()
        loadDownloadedFiles()
    }

    // MARK: - Private Methods

    private func loadDownloadedFiles() {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files {
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
