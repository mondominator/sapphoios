import XCTest
@testable import Sappho

/// CarPlay's Now Playing showed the chapter name as the title ("Chapter 12"),
/// so the car never said which book was playing.
final class NowPlayingTextTests: XCTestCase {

    private func lines(chapter: String? = "The Storm", number: Int? = 12, count: Int? = 40,
                       series: String? = "Saga", waiting: Bool = false) -> NowPlayingText.Lines {
        NowPlayingText.lines(bookTitle: "The Bone People", author: "Keri Hulme", series: series,
                             chapterTitle: chapter, chapterNumber: number, chapterCount: count, waiting: waiting)
    }

    func testTitleIsTheBookAndTheChapterIsTheSecondLine() {
        XCTAssertEqual(lines(), .init(title: "The Bone People", artist: "Keri Hulme", album: "Ch 12 of 40: The Storm"))
    }

    func testChapterNamesThatOnlyRepeatTheNumberAreDropped() {
        for filler in ["Chapter 12", "chapter 12", "12", "Ch. 12", "Track 12", "  ", "The Bone People"] {
            XCTAssertEqual(lines(chapter: filler).album, "Ch 12 of 40", filler)
        }
        XCTAssertEqual(lines(chapter: nil).album, "Ch 12 of 40")
    }

    func testWithoutAChapterTheSeriesStays() {
        XCTAssertEqual(lines(chapter: nil, number: nil, count: nil).album, "Saga")
        XCTAssertEqual(lines(chapter: nil, number: nil, count: nil, series: nil).album, nil)
    }

    func testSingleChapterBooksDoNotSayOfOne() {
        XCTAssertEqual(lines(chapter: "Intro", number: 1, count: 1).album, "Ch 1: Intro")
    }

    func testBufferingTakesTheSecondLine() {
        XCTAssertEqual(lines(waiting: true).album, "Buffering…")
        XCTAssertEqual(lines(waiting: true).title, "The Bone People")
    }

    func testMissingAuthorFallsBack() {
        let result = NowPlayingText.lines(bookTitle: "B", author: nil, series: nil, chapterTitle: nil,
                                          chapterNumber: nil, chapterCount: nil, waiting: false)
        XCTAssertEqual(result.artist, "Unknown Author")
    }

    // MARK: - ChapterProgressSetting

    func testChapterProgressDefaultsToOnLikeTheAppToggle() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        XCTAssertTrue(ChapterProgressSetting.isOn(defaults))
        defaults.set(false, forKey: ChapterProgressSetting.key)
        XCTAssertFalse(ChapterProgressSetting.isOn(defaults))
        defaults.removePersistentDomain(forName: #function)
    }
}
