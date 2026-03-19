import XCTest
@testable import Sappho

final class DownloadManagerTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - DownloadState Equality

    func testDownloadStateNotDownloadedEquality() {
        let a = DownloadState.notDownloaded
        let b = DownloadState.notDownloaded
        XCTAssertEqual(a, b)
    }

    func testDownloadStateDownloadingEquality() {
        let a = DownloadState.downloading(progress: 0.5)
        let b = DownloadState.downloading(progress: 0.5)
        XCTAssertEqual(a, b)
    }

    func testDownloadStateDownloadingInequality() {
        let a = DownloadState.downloading(progress: 0.5)
        let b = DownloadState.downloading(progress: 0.8)
        XCTAssertNotEqual(a, b)
    }

    func testDownloadStateDownloadedEquality() {
        let url = URL(string: "file:///test/book.m4b")!
        let a = DownloadState.downloaded(localURL: url)
        let b = DownloadState.downloaded(localURL: url)
        XCTAssertEqual(a, b)
    }

    func testDownloadStateDownloadedInequality() {
        let a = DownloadState.downloaded(localURL: URL(string: "file:///test/a.m4b")!)
        let b = DownloadState.downloaded(localURL: URL(string: "file:///test/b.m4b")!)
        XCTAssertNotEqual(a, b)
    }

    func testDownloadStateFailedEquality() {
        let a = DownloadState.failed(message: "Disk full")
        let b = DownloadState.failed(message: "Disk full")
        XCTAssertEqual(a, b)
    }

    func testDownloadStateFailedInequality() {
        let a = DownloadState.failed(message: "Disk full")
        let b = DownloadState.failed(message: "Network error")
        XCTAssertNotEqual(a, b)
    }

    func testDownloadStateDifferentCasesNotEqual() {
        let notDownloaded = DownloadState.notDownloaded
        let downloading = DownloadState.downloading(progress: 0.5)
        let downloaded = DownloadState.downloaded(localURL: URL(string: "file:///test.m4b")!)
        let failed = DownloadState.failed(message: "Error")

        XCTAssertNotEqual(notDownloaded, downloading)
        XCTAssertNotEqual(notDownloaded, downloaded)
        XCTAssertNotEqual(notDownloaded, failed)
        XCTAssertNotEqual(downloading, downloaded)
        XCTAssertNotEqual(downloading, failed)
        XCTAssertNotEqual(downloaded, failed)
    }

    // MARK: - DownloadedBookMeta

    func testDownloadedBookMetaFromAudiobook() {
        let progress = Progress(position: 500, completed: 0)
        let chapters = [
            Chapter(id: 1, audiobookId: 42, chapterNumber: 1, startTime: 0, duration: 600, title: "Ch 1"),
            Chapter(id: 2, audiobookId: 42, chapterNumber: 2, startTime: 600, duration: 900, title: "Ch 2"),
        ]
        let audiobook = Audiobook(
            id: 42,
            title: "Test Book",
            author: "Author Name",
            narrator: "Narrator Name",
            series: "Series Name",
            seriesPosition: 2.0,
            duration: 3600,
            genre: "Fiction",
            coverImage: "cover.jpg",
            progress: progress,
            chapters: chapters
        )

        let meta = DownloadedBookMeta(from: audiobook)

        XCTAssertEqual(meta.id, 42)
        XCTAssertEqual(meta.title, "Test Book")
        XCTAssertEqual(meta.author, "Author Name")
        XCTAssertEqual(meta.narrator, "Narrator Name")
        XCTAssertEqual(meta.series, "Series Name")
        XCTAssertEqual(meta.seriesPosition, 2.0)
        XCTAssertEqual(meta.duration, 3600)
        XCTAssertEqual(meta.genre, "Fiction")
        XCTAssertEqual(meta.coverImage, "cover.jpg")
        XCTAssertEqual(meta.lastPosition, 500)
        XCTAssertEqual(meta.completed, 0)
        XCTAssertEqual(meta.chapters?.count, 2)
    }

    func testDownloadedBookMetaFromMinimalAudiobook() {
        let audiobook = Audiobook(id: 1, title: "Minimal")
        let meta = DownloadedBookMeta(from: audiobook)

        XCTAssertEqual(meta.id, 1)
        XCTAssertEqual(meta.title, "Minimal")
        XCTAssertNil(meta.author)
        XCTAssertNil(meta.narrator)
        XCTAssertNil(meta.series)
        XCTAssertNil(meta.duration)
        XCTAssertNil(meta.lastPosition)
        XCTAssertNil(meta.completed)
        XCTAssertNil(meta.chapters)
    }

    func testDownloadedBookMetaToAudiobook() {
        let progress = Progress(position: 300, completed: 0)
        let chapters = [
            Chapter(id: 1, audiobookId: 10, chapterNumber: 1, startTime: 0, duration: 600, title: "Intro"),
        ]
        let original = Audiobook(
            id: 10,
            title: "Original Book",
            author: "Original Author",
            duration: 7200,
            progress: progress,
            chapters: chapters
        )

        let meta = DownloadedBookMeta(from: original)
        let restored = meta.toAudiobook()

        XCTAssertEqual(restored.id, 10)
        XCTAssertEqual(restored.title, "Original Book")
        XCTAssertEqual(restored.author, "Original Author")
        XCTAssertEqual(restored.duration, 7200)
        XCTAssertEqual(restored.progress?.position, 300)
        XCTAssertEqual(restored.chapters?.count, 1)
        XCTAssertEqual(restored.chapters?.first?.title, "Intro")
    }

    func testDownloadedBookMetaToAudiobookNoProgress() {
        let audiobook = Audiobook(id: 5, title: "No Progress")
        let meta = DownloadedBookMeta(from: audiobook)
        let restored = meta.toAudiobook()

        XCTAssertNil(restored.progress, "Audiobook without progress should restore with nil progress")
    }

    func testDownloadedBookMetaCodable() throws {
        let audiobook = Audiobook(
            id: 42,
            title: "Codable Book",
            author: "Test Author",
            duration: 1800
        )
        let meta = DownloadedBookMeta(from: audiobook)

        let encoded = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(DownloadedBookMeta.self, from: encoded)

        XCTAssertEqual(decoded.id, 42)
        XCTAssertEqual(decoded.title, "Codable Book")
        XCTAssertEqual(decoded.author, "Test Author")
        XCTAssertEqual(decoded.duration, 1800)
    }

    // MARK: - CachedChapter

    func testCachedChapterFromChapter() {
        let chapter = Chapter(id: 5, audiobookId: 10, chapterNumber: 3, startTime: 1200.0, duration: 600.0, title: "Chapter 3")
        let cached = CachedChapter(from: chapter)

        XCTAssertEqual(cached.id, 5)
        XCTAssertEqual(cached.audiobookId, 10)
        XCTAssertEqual(cached.chapterNumber, 3)
        XCTAssertEqual(cached.startTime, 1200.0)
        XCTAssertEqual(cached.duration, 600.0)
        XCTAssertEqual(cached.title, "Chapter 3")
    }

    func testCachedChapterToChapter() {
        let chapter = Chapter(id: 1, audiobookId: 2, chapterNumber: 1, startTime: 0, duration: 300, title: "Prologue")
        let cached = CachedChapter(from: chapter)
        let restored = cached.toChapter()

        XCTAssertEqual(restored.id, 1)
        XCTAssertEqual(restored.audiobookId, 2)
        XCTAssertEqual(restored.chapterNumber, 1)
        XCTAssertEqual(restored.startTime, 0)
        XCTAssertEqual(restored.duration, 300)
        XCTAssertEqual(restored.title, "Prologue")
    }

    func testCachedChapterRoundTrip() throws {
        let chapter = Chapter(id: 99, audiobookId: 50, chapterNumber: 10, startTime: 5000.5, duration: 1200.0, title: "The Climax")
        let cached = CachedChapter(from: chapter)

        let encoded = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedChapter.self, from: encoded)

        let restored = decoded.toChapter()
        XCTAssertEqual(restored.id, 99)
        XCTAssertEqual(restored.audiobookId, 50)
        XCTAssertEqual(restored.chapterNumber, 10)
        XCTAssertEqual(restored.startTime, 5000.5, accuracy: 0.01)
        XCTAssertEqual(restored.duration, 1200.0)
        XCTAssertEqual(restored.title, "The Climax")
    }

    func testCachedChapterWithNilDuration() {
        let chapter = Chapter(id: 1, audiobookId: 1, chapterNumber: 1, startTime: 0, duration: nil, title: nil)
        let cached = CachedChapter(from: chapter)

        XCTAssertNil(cached.duration)
        XCTAssertNil(cached.title)

        let restored = cached.toChapter()
        XCTAssertNil(restored.duration)
        XCTAssertNil(restored.title)
    }
}
