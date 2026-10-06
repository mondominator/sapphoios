import CarPlay
import UIKit

/// Fetches data from SapphoAPI and builds CPListItem arrays for CarPlay templates.
@MainActor
final class CarPlayContentProvider {

    private let api: SapphoAPI

    init(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Home

    /// The Home sections, fetched from the server.
    ///
    /// Split out from `homeTemplate` so the scene delegate can present an empty
    /// Home immediately and fill it in when the network answers. CarPlay
    /// terminates an app that has not set a root template shortly after
    /// connecting, and in a car the server is often slow or unreachable.
    func homeSections(onSelect: @escaping (Audiobook) -> Void) async -> [CPListSection] {
        var sections: [CPListSection] = []

        // No signal (common in a car): don't sit on requests that cannot
        // succeed. Offer what plays without the server instead of a blank Home.
        guard NetworkMonitor.shared.isConnected,
              let inProgress = try? await api.getInProgress(limit: 25) else {
            return offlineSections(onSelect: onSelect)
        }

        // Resume, on its own, first. In a car the overwhelmingly common intent
        // is "carry on with the thing I was listening to" -- making that the
        // top row means one glance and one tap instead of scanning a section.

        if let current = inProgress.first {
            let resume = listItem(for: current, onSelect: onSelect)
            sections.append(CPListSection(items: [resume], header: "Resume", sectionIndexTitle: nil))
        }

        // Everything else still in flight, minus the one promoted above.
        let rest = Array(inProgress.dropFirst())
        if !rest.isEmpty {
            let items = rest.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
            sections.append(CPListSection(items: items, header: "In Progress", sectionIndexTitle: nil))
        }

        // Up Next
        if let books = try? await api.getUpNext(), !books.isEmpty {
            let items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
            sections.append(CPListSection(items: items, header: "Up Next", sectionIndexTitle: nil))
        }

        // Recently Added
        if let books = try? await api.getRecentlyAdded(limit: 10), !books.isEmpty {
            let items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
            sections.append(CPListSection(items: items, header: "Recently Added", sectionIndexTitle: nil))
        }

        // Listen Again
        if let books = try? await api.getFinished(limit: 10), !books.isEmpty {
            let items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
            sections.append(CPListSection(items: items, header: "Listen Again", sectionIndexTitle: nil))
        }

        return sections
    }

    /// Home when the server can't be reached: the loaded book (if any) and
    /// the downloaded books, which play from local files.
    func offlineSections(onSelect: @escaping (Audiobook) -> Void) -> [CPListSection] {
        var sections: [CPListSection] = []
        let downloaded = downloadedBooks()

        if let current = ServiceLocator.shared.audioPlayer?.currentAudiobook {
            sections.append(CPListSection(items: [listItem(for: current, onSelect: onSelect)], header: "Resume", sectionIndexTitle: nil))
        }
        if !downloaded.isEmpty {
            let items = downloaded.prefix(100).map { listItem(for: $0, onSelect: onSelect) }
            sections.append(CPListSection(items: items, header: "Downloaded", sectionIndexTitle: nil))
        }
        if sections.isEmpty {
            let item = CPListItem(text: "Can't reach your Sappho server", detailText: "Downloaded books appear here when you're offline.")
            sections.append(CPListSection(items: [item]))
        }
        return sections
    }

    // MARK: - Downloaded

    func downloadedTemplate(onSelect: @escaping (Audiobook) -> Void) -> CPListTemplate {
        let books = downloadedBooks()
        let items: [CPListItem]
        if books.isEmpty {
            items = [CPListItem(text: "No downloaded books", detailText: "Download books on your phone to listen offline.")]
        } else {
            items = books.prefix(100).map { listItem(for: $0, onSelect: onSelect) }
        }
        return CPListTemplate(title: "Downloaded", sections: [CPListSection(items: items)])
    }

    private func downloadedBooks() -> [Audiobook] {
        DownloadManager.shared.downloadedAudiobooks()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Library

    func libraryTemplate(
        onDownloaded: @escaping () -> Void,
        onAuthors: @escaping () -> Void,
        onSeries: @escaping () -> Void,
        onCollections: @escaping () -> Void,
        onAllBooks: @escaping () -> Void
    ) -> CPListTemplate {
        // No Search row: CPSearchTemplate is only for navigation apps, and
        // CarPlay rejects it from an audio app whether it is a tab or pushed.
        // Downloaded is the useful extra row in a car with patchy signal.
        let downloadedItem = CPListItem(
            text: "Downloaded",
            detailText: nil,
            image: UIImage(systemName: "arrow.down.circle")
        )
        downloadedItem.accessoryType = .disclosureIndicator
        downloadedItem.handler = { _, completion in
            onDownloaded()
            completion()
        }

        let authorsItem = CPListItem(
            text: "Authors",
            detailText: nil,
            image: UIImage(systemName: "person.2")
        )
        authorsItem.accessoryType = .disclosureIndicator
        authorsItem.handler = { _, completion in
            onAuthors()
            completion()
        }

        let seriesItem = CPListItem(
            text: "Series",
            detailText: nil,
            image: UIImage(systemName: "books.vertical")
        )
        seriesItem.accessoryType = .disclosureIndicator
        seriesItem.handler = { _, completion in
            onSeries()
            completion()
        }

        let collectionsItem = CPListItem(
            text: "Collections",
            detailText: nil,
            image: UIImage(systemName: "folder")
        )
        collectionsItem.accessoryType = .disclosureIndicator
        collectionsItem.handler = { _, completion in
            onCollections()
            completion()
        }

        let allBooksItem = CPListItem(
            text: "All Books",
            detailText: nil,
            image: UIImage(systemName: "book.closed")
        )
        allBooksItem.accessoryType = .disclosureIndicator
        allBooksItem.handler = { _, completion in
            onAllBooks()
            completion()
        }

        let section = CPListSection(items: [downloadedItem, authorsItem, seriesItem, collectionsItem, allBooksItem])
        return CPListTemplate(title: "Library", sections: [section])
    }

    // MARK: - Authors

    func authorsListTemplate(onSelect: @escaping (String) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let authors = try? await api.getAuthors() {
            items = authors.prefix(100).map { authorInfo in
                let item = CPListItem(
                    text: authorInfo.author,
                    detailText: "\(authorInfo.bookCount) book\(authorInfo.bookCount == 1 ? "" : "s")"
                )
                item.accessoryType = .disclosureIndicator
                item.handler = { _, completion in
                    onSelect(authorInfo.author)
                    completion()
                }
                return item
            }
        }

        return CPListTemplate(title: "Authors", sections: [CPListSection(items: items)])
    }

    // MARK: - Series

    func seriesListTemplate(onSelect: @escaping (String) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let seriesList = try? await api.getSeries() {
            items = seriesList.prefix(100).map { seriesInfo in
                let item = CPListItem(
                    text: seriesInfo.series,
                    detailText: "\(seriesInfo.bookCount) book\(seriesInfo.bookCount == 1 ? "" : "s")"
                )
                item.accessoryType = .disclosureIndicator
                item.handler = { _, completion in
                    onSelect(seriesInfo.series)
                    completion()
                }
                return item
            }
        }

        return CPListTemplate(title: "Series", sections: [CPListSection(items: items)])
    }

    // MARK: - Collections

    func collectionsListTemplate(onSelect: @escaping (Collection) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let collections = try? await api.getCollections() {
            items = collections.prefix(100).map { collection in
                let bookCount = collection.bookCount ?? 0
                let item = CPListItem(
                    text: collection.name,
                    detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
                )
                item.accessoryType = .disclosureIndicator
                item.handler = { _, completion in
                    onSelect(collection)
                    completion()
                }
                return item
            }
        }

        return CPListTemplate(title: "Collections", sections: [CPListSection(items: items)])
    }

    // MARK: - Books for Author

    func booksForAuthor(_ author: String, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let books = try? await api.getAudiobooksByAuthor(author) {
            items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
        }

        return CPListTemplate(title: author, sections: [CPListSection(items: items)])
    }

    // MARK: - Books for Series

    func booksForSeries(_ series: String, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let books = try? await api.getAudiobooksBySeries(series) {
            let sorted = books.sorted { ($0.seriesPosition ?? 0) < ($1.seriesPosition ?? 0) }
            items = sorted.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
        }

        return CPListTemplate(title: series, sections: [CPListSection(items: items)])
    }

    // MARK: - Books for Collection

    func booksForCollection(_ collection: Collection, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let detail = try? await api.getCollection(id: collection.id) {
            items = detail.books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
        }

        return CPListTemplate(title: collection.name, sections: [CPListSection(items: items)])
    }

    // MARK: - All Books

    func allBooksTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let books = try? await api.getAudiobooks() {
            items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
        }

        return CPListTemplate(title: "All Books", sections: [CPListSection(items: items)])
    }

    // MARK: - Helpers

    private func listItem(for book: Audiobook, onSelect: @escaping (Audiobook) -> Void) -> CPListItem {
        var detailParts: [String] = []

        if let author = book.author {
            detailParts.append(author)
        }

        if let progress = book.progress, let duration = book.duration, duration > 0 {
            // "4h 12m left" is what a driver can act on at a glance; a bare
            // percentage makes them do the arithmetic.
            let remaining = max(0, duration - progress.position)
            detailParts.append("\(formatDuration(remaining)) left")
        } else if let duration = book.duration {
            detailParts.append(formatDuration(duration))
        }

        let detail = detailParts.joined(separator: " · ")

        let item = CPListItem(text: book.title, detailText: detail.isEmpty ? nil : detail)
        item.handler = { _, completion in
            onSelect(book)
            completion()
        }

        // Load thumbnail asynchronously
        loadThumbnail(for: book.id, into: item)

        return item
    }

    private func loadThumbnail(for bookId: Int, into item: CPListItem) {
        guard let coverURL = api.coverURL(for: bookId) else { return }

        let cacheKey = coverURL.absoluteString

        // Check cache first
        if let cached = ImageCache.shared.image(for: cacheKey) {
            let thumbnail = Self.resizedImage(cached, to: CGSize(width: 90, height: 90))
            item.setImage(thumbnail)
            return
        }

        // Capture auth headers for authenticated request
        let authHeaders = api.authHeaders

        // Load asynchronously with authentication
        Task {
            do {
                var request = URLRequest(url: coverURL)
                for (field, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: field)
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      let image = UIImage(data: data) else { return }

                ImageCache.shared.setImage(image, for: cacheKey)
                let thumbnail = Self.resizedImage(image, to: CGSize(width: 90, height: 90))
                await MainActor.run {
                    item.setImage(thumbnail)
                }
            } catch {
                // Silently fail — item will show without thumbnail
            }
        }
    }

    private static func resizedImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
