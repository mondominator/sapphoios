import XCTest
@testable import Sappho

/// Which book "play …" means. Requests are phrased the way Siri hands them
/// over (its `mediaName` / `artistName`), not the way the library titles them.
final class VoiceSearchTests: XCTestCase {

    private func book(
        _ id: Int, _ title: String, author: String? = nil, series: String? = nil,
        position: Int? = nil, seriesPosition: Float? = nil
    ) -> Audiobook {
        var fields: [String] = [#""id":\#(id)"#, #""title":"\#(title)""#, #""duration":3600"#]
        if let author { fields.append(#""author":"\#(author)""#) }
        if let series { fields.append(#""series":"\#(series)""#) }
        if let seriesPosition { fields.append(#""series_position":\#(seriesPosition)"#) }
        if let position { fields.append(#""progress":{"position":\#(position),"completed":0}"#) }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try! JSONDecoder().decode(Audiobook.self, from: Data(json.utf8))
    }

    func testNormalizeIgnoresCaseAccentsPunctuationAndFillerWords() {
        XCTAssertEqual(VoiceSearch.normalize("The Bone People"), "bone people")
        XCTAssertEqual(VoiceSearch.normalize("the bone people audiobook"), "bone people")
        XCTAssertEqual(VoiceSearch.normalize("Les Misérables"), "les miserables")
        XCTAssertEqual(VoiceSearch.normalize("Harry Potter & the Goblet of Fire"), "harry potter and the goblet of fire")
        XCTAssertEqual(VoiceSearch.normalize("Project Hail-Mary!"), "project hail mary")
        XCTAssertEqual(VoiceSearch.normalize("The"), "the", "a lone article is a title, not filler")
    }

    func testQueryPrefersTheNameAndFallsBackToTheAuthor() {
        XCTAssertEqual(VoiceSearch.query(mediaName: "The Bone People", artistName: nil), "bone people")
        XCTAssertEqual(VoiceSearch.query(mediaName: nil, artistName: "Keri Hulme"), "keri hulme")
        XCTAssertEqual(VoiceSearch.query(mediaName: "audiobook", artistName: "Keri Hulme"), "keri hulme")
    }

    func testARequestNamingNothingMeansTheCurrentBook() {
        XCTAssertNil(VoiceSearch.query(mediaName: nil, artistName: nil))
        XCTAssertNil(VoiceSearch.query(mediaName: "my audiobook", artistName: nil))
        XCTAssertNil(VoiceSearch.query(mediaName: "  ", artistName: ""))
    }

    func testAnExactTitleBeatsOneThatOnlyContainsIt() {
        let books = [
            book(1, "The Bone People Companion"),
            book(2, "The Bone People", author: "Keri Hulme"),
            book(3, "People of the Bone")
        ]
        XCTAssertEqual(VoiceSearch.bestMatch("bone people", in: books)?.id, 2)
    }

    func testATitleBeatsAnAuthorWithTheSameWord() {
        let books = [
            book(1, "Some Novel", author: "Carl Hiaasen"),
            book(2, "Dungeon Crawler Carl", author: "Matt Dinniman")
        ]
        XCTAssertEqual(VoiceSearch.bestMatch("dungeon crawler carl", in: books)?.id, 2)
        XCTAssertEqual(VoiceSearch.ranked("carl", in: books).map(\.id), [2, 1])
    }

    func testASeriesNamePicksTheBookInProgressThenTheFirst() {
        let series = [
            book(3, "The Gate of the Feral Gods", series: "Dungeon Crawler Carl", seriesPosition: 4),
            book(1, "Dungeon Crawler Carl", series: "Dungeon Crawler Carl", seriesPosition: 1),
            book(2, "Carl's Doomsday Scenario", series: "Dungeon Crawler Carl", position: 1200, seriesPosition: 2)
        ]
        // The first book's title matches exactly, so it wins outright...
        XCTAssertEqual(VoiceSearch.bestMatch("dungeon crawler carl", in: series)?.id, 1)

        // ...but a series without such a title goes to the one in progress.
        let other = [
            book(5, "Leviathan Wakes", series: "The Expanse", seriesPosition: 1),
            book(6, "Caliban's War", series: "The Expanse", position: 300, seriesPosition: 2)
        ]
        XCTAssertEqual(VoiceSearch.bestMatch("the expanse", in: other)?.id, 6)
    }

    func testAnAuthorRequestFindsTheirBooks() {
        let books = [book(1, "Unrelated"), book(2, "The Bone People", author: "Keri Hulme")]
        XCTAssertEqual(VoiceSearch.bestMatch("keri hulme", in: books)?.id, 2)
        XCTAssertEqual(VoiceSearch.bestMatch("hulme", in: books)?.id, 2)
    }

    func testNoMatchIsNilAndDuplicatesCountOnce() {
        let books = [book(1, "The Bone People"), book(1, "The Bone People")]
        XCTAssertNil(VoiceSearch.bestMatch("project hail mary", in: books))
        XCTAssertEqual(VoiceSearch.ranked("bone people", in: books).count, 1,
                       "a book from the server and the same book downloaded is one result")
    }
}
