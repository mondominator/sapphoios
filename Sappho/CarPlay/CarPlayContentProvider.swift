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

    func homeTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var sections: [CPListSection] = []

        // Continue Listening
        if let books = try? await api.getInProgress(limit: 10), !books.isEmpty {
            let items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
            sections.append(CPListSection(items: items, header: "Continue Listening", sectionIndexTitle: nil))
        }

        // Up Next
        if let books = try? await api.getUpNext(limit: 10), !books.isEmpty {
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

        return CPListTemplate(title: "Home", sections: sections)
    }

    // MARK: - Library

    func libraryTemplate(
        onAuthors: @escaping () -> Void,
        onSeries: @escaping () -> Void,
        onCollections: @escaping () -> Void,
        onAllBooks: @escaping () -> Void
    ) -> CPListTemplate {
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

        let section = CPListSection(items: [authorsItem, seriesItem, collectionsItem, allBooksItem])
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

    // MARK: - Reading List

    func readingListTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        var items: [CPListItem] = []

        if let books = try? await api.getFavorites(sort: "custom") {
            items = books.prefix(100).map { book in
                listItem(for: book, onSelect: onSelect)
            }
        }

        return CPListTemplate(title: "Reading List", sections: [CPListSection(items: items)])
    }

    // MARK: - Helpers

    private func listItem(for book: Audiobook, onSelect: @escaping (Audiobook) -> Void) -> CPListItem {
        var detailParts: [String] = []

        if let author = book.author {
            detailParts.append(author)
        }

        if let progress = book.progress, let duration = book.duration, duration > 0 {
            let percent = Int(Double(progress.position) / Double(duration) * 100)
            detailParts.append("\(percent)%")
        } else if let duration = book.duration {
            detailParts.append(Self.formatDuration(duration))
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

    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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

        // Load asynchronously
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: coverURL)
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
