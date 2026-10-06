import CarPlay
import UIKit

/// Builds CarPlay lists. Home comes from data already on the device
/// (`HomeFeedStore`, downloads, the current book); library lists come from the
/// server and are pushed with a loading row first (see CarPlaySceneDelegate).
@MainActor
final class CarPlayContentProvider {

    private let api: SapphoAPI
    private let coverLoader: CoverThumbnailLoader

    init(api: SapphoAPI, coverLoader: CoverThumbnailLoader = .shared) {
        self.api = api
        self.coverLoader = coverLoader
    }

    // MARK: - Home

    /// Home as it stands right now, built only from what is on the device:
    /// the saved feed (refreshed in the background by `HomeFeedStore`), the
    /// current book and the downloads. Never waits on the network, so it can
    /// be shown the instant CarPlay connects and rebuilt as each section of
    /// the feed answers.
    func homeSections(
        store: HomeFeedStore,
        onSelect: @escaping (Audiobook) -> Void,
        onRetry: @escaping () -> Void
    ) -> [CPListSection] {
        let downloaded = downloadedBooks()
        let current = CarPlayHomeLayout.currentBook(
            loaded: ServiceLocator.shared.audioPlayer?.currentAudiobook,
            lastPlayedId: AudioPlayerService.lastPlayedAudiobookId,
            downloaded: downloaded,
            feed: store.sections
        )
        let layout = CarPlayHomeLayout.build(
            feed: store.sections,
            downloaded: downloaded,
            current: current,
            isConnected: NetworkMonitor.shared.isConnected
        )
        return layout.map { section in
            let items = section.rows.map { row -> CPListItem in
                switch row {
                case .book(let book, let isDownloaded):
                    return listItem(for: book, isDownloaded: isDownloaded, onSelect: onSelect)
                case .status(let title, let detail, let retry):
                    let item = CPListItem(text: title, detailText: detail)
                    if retry {
                        item.handler = { _, completion in
                            onRetry()
                            completion()
                        }
                    }
                    return item
                }
            }
            return CPListSection(items: items, header: section.header, sectionIndexTitle: nil)
        }
    }

    // MARK: - Downloaded

    func downloadedTemplate(onSelect: @escaping (Audiobook) -> Void) -> CPListTemplate {
        let books = downloadedBooks()
        let items: [CPListItem]
        if books.isEmpty {
            items = [CPListItem(text: "No downloaded books", detailText: "Download books on your phone to listen offline.")]
        } else {
            items = books.prefix(100).map { listItem(for: $0, isDownloaded: true, onSelect: onSelect) }
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

    // MARK: - Library lists
    //
    // Each returns the rows for a pushed list. The scene delegate pushes the
    // list at once with a "Loading…" row and fills it in when this returns,
    // so a tap always does something even when the server is slow.

    func authorsSections(onSelect: @escaping (String) -> Void) async throws -> [CPListSection] {
        let authors = try await api.getAuthors()
        let items = authors.prefix(CarPlayHomeLayout.maxRowsPerSection * 4).map { authorInfo in
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
        return [CPListSection(items: Array(items))]
    }

    func seriesSections(onSelect: @escaping (String) -> Void) async throws -> [CPListSection] {
        let seriesList = try await api.getSeries()
        let items = seriesList.prefix(CarPlayHomeLayout.maxRowsPerSection * 4).map { seriesInfo in
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
        return [CPListSection(items: Array(items))]
    }

    func collectionsSections(onSelect: @escaping (Collection) -> Void) async throws -> [CPListSection] {
        let collections = try await api.getCollections()
        let items = collections.prefix(CarPlayHomeLayout.maxRowsPerSection * 4).map { collection in
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
        return [CPListSection(items: Array(items))]
    }

    func booksForAuthorSections(_ author: String, onSelect: @escaping (Audiobook) -> Void) async throws -> [CPListSection] {
        bookSections(try await api.getAudiobooksByAuthor(author), onSelect: onSelect)
    }

    func booksForSeriesSections(_ series: String, onSelect: @escaping (Audiobook) -> Void) async throws -> [CPListSection] {
        let books = try await api.getAudiobooksBySeries(series)
        return bookSections(books.sorted { ($0.seriesPosition ?? 0) < ($1.seriesPosition ?? 0) }, onSelect: onSelect)
    }

    func booksForCollectionSections(_ collection: Collection, onSelect: @escaping (Audiobook) -> Void) async throws -> [CPListSection] {
        bookSections(try await api.getCollection(id: collection.id).books, onSelect: onSelect)
    }

    func allBooksSections(onSelect: @escaping (Audiobook) -> Void) async throws -> [CPListSection] {
        bookSections(try await api.getAudiobooks(), onSelect: onSelect)
    }

    private func bookSections(_ books: [Audiobook], onSelect: @escaping (Audiobook) -> Void) -> [CPListSection] {
        let downloadedIds = Set(DownloadManager.shared.downloadedAudiobooks().map(\.id))
        let items = books.prefix(100).map {
            listItem(for: $0, isDownloaded: downloadedIds.contains($0.id), onSelect: onSelect)
        }
        return [CPListSection(items: Array(items))]
    }

    // MARK: - Helpers

    private func listItem(for book: Audiobook, isDownloaded: Bool = false, onSelect: @escaping (Audiobook) -> Void) -> CPListItem {
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

        if isDownloaded {
            detailParts.append("Downloaded")
        }

        let detail = detailParts.joined(separator: " · ")

        let item = CPListItem(text: book.title, detailText: detail.isEmpty ? nil : detail)
        item.handler = { _, completion in
            onSelect(book)
            completion()
        }

        // The row is shown now; its cover arrives when it arrives. A cached
        // cover (this size or the phone's original) is set synchronously.
        coverLoader.load(audiobookId: book.id, width: CoverURL.listThumbnailWidth, api: api) { [weak item] image in
            guard let item, let image else { return }
            item.setImage(Self.thumbnail(image, maxSize: CPListItem.maximumImageSize))
        }

        return item
    }

    /// Scale to fit (keeping the aspect ratio) within CarPlay's row image size.
    private static func thumbnail(_ image: UIImage, maxSize: CGSize) -> UIImage {
        let scale = min(maxSize.width / max(image.size.width, 1), maxSize.height / max(image.size.height, 1), 1)
        guard scale < 1 else { return image }
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
