import Foundation

/// Picking the book a spoken request means ("play The Bone People",
/// "play Dungeon Crawler Carl", "play something by Keri Hulme"). Pure, so the
/// rules are unit tested; `PlayMediaIntentHandler` feeds it Siri's parsed
/// request and the books the server (or the downloads) offered.
///
/// Siri hands over what it heard, not what the library calls it: casing,
/// punctuation, a leading "the" and words like "audiobook" vary. So both
/// sides are normalized, and a title match outranks a series or author
/// match -- "play Carl" should not pick an author named Carl over a title.
/// Among equal matches, a book already in progress wins: in a car, "play X"
/// usually means "carry on with X".
enum VoiceSearch {

    /// The text to search for, or nil when the request names nothing
    /// ("play my audiobook", "resume") and the current book should play.
    static func query(mediaName: String?, artistName: String?) -> String? {
        let name = normalize(mediaName ?? "")
        if !name.isEmpty, !genericNames.contains(name) { return name }
        let artist = normalize(artistName ?? "")
        return artist.isEmpty ? nil : artist
    }

    /// The best book for `query`, or nil when none matches at all.
    static func bestMatch(_ query: String, in books: [Audiobook]) -> Audiobook? {
        ranked(query, in: books).first
    }

    /// Matching books, best first.
    static func ranked(_ query: String, in books: [Audiobook]) -> [Audiobook] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        var seen = Set<Int>()
        let scored = books.compactMap { book -> (Audiobook, Int)? in
            guard seen.insert(book.id).inserted else { return nil }
            let score = self.score(q, book)
            return score > 0 ? (book, score) : nil
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let ia = isInProgress(a.0), ib = isInProgress(b.0)
            if ia != ib { return ia }
            return (a.0.seriesPosition ?? 0) < (b.0.seriesPosition ?? 0)
        }.map(\.0)
    }

    // MARK: - Scoring

    private static func score(_ q: String, _ book: Audiobook) -> Int {
        let title = normalize(book.title)
        let series = normalize(book.series ?? "")
        let author = normalize(book.author ?? "")
        let qWords = Set(q.split(separator: " "))

        if title == q { return 100 }
        if title.hasPrefix(q + " ") || title.hasPrefix(q) && q.count >= 4 { return 85 }
        if !series.isEmpty, series == q { return 75 }
        if title.contains(q) { return 70 }
        if !qWords.isEmpty, qWords.isSubset(of: Set(title.split(separator: " "))) { return 60 }
        if !series.isEmpty, series.contains(q) { return 55 }
        if !author.isEmpty, author == q || author.contains(q) { return 50 }
        if !author.isEmpty, !qWords.isEmpty, qWords.isSubset(of: Set(author.split(separator: " "))) { return 45 }
        return 0
    }

    private static func isInProgress(_ book: Audiobook) -> Bool {
        guard let progress = book.progress else { return false }
        return progress.position > 0 && progress.completed != 1
    }

    // MARK: - Normalizing

    /// Requests that name no book: play whatever is current.
    /// (Compared after `normalize`, which strips a trailing "audiobook", so
    /// "my audiobook" arrives here as "my".)
    private static let genericNames: Set<String> = [
        "audiobook", "audiobooks", "my", "my audiobooks", "my book", "book", "sappho", "something"
    ]

    /// Words Siri keeps that a title doesn't have.
    private static let fillerWords: Set<String> = ["audiobook", "audio book", "the audiobook"]

    /// Lowercased, accents folded, punctuation dropped, spaces collapsed,
    /// a leading "the"/"a"/"an" and a trailing "audiobook" removed.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var words = String(cleaned).split(separator: " ").map(String.init)
        if words.count > 1, ["the", "a", "an"].contains(words[0]) { words.removeFirst() }
        if words.count > 1, words.last == "audiobook" { words.removeLast() }
        if words.count > 2, words.suffix(2) == ["audio", "book"] { words.removeLast(2) }
        let joined = words.joined(separator: " ")
        return fillerWords.contains(joined) ? "audiobook" : joined
    }
}
