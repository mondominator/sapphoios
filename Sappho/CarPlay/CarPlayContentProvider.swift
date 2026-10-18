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
        onOpenShelf: @escaping (String, [Audiobook]) -> Void,
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
        // One row of covers per section, as the phone's Home shows each as a
        // row of cards; status rows stay plain list rows.
        var items: [CPListTemplateItem] = []
        for section in layout {
            let books = section.rows.compactMap { row -> Audiobook? in
                if case .book(let book, _) = row { return book }
                return nil
            }
            if let header = section.header, !books.isEmpty {
                items.append(shelfItem(
                    title: header,
                    books: books,
                    showProgress: header == CarPlayHomeLayout.continueListeningHeader,
                    onSelect: onSelect,
                    onOpen: onOpenShelf
                ))
                continue
            }
            for row in section.rows {
                guard case .status(let title, let detail, let retry) = row else { continue }
                let item = CPListItem(text: title, detailText: detail)
                if retry {
                    item.handler = { _, completion in
                        onRetry()
                        completion()
                    }
                }
                items.append(item)
            }
        }
        return [CPListSection(items: items)]
    }

    /// The rows of a Home section as a plain list, for "see all" from its
    /// title. Built from the books already on screen: no network.
    func shelfSections(_ books: [Audiobook], onSelect: @escaping (Audiobook) -> Void) -> [CPListSection] {
        bookSections(books, onSelect: onSelect)
    }

    /// A Home section as one row of covers: tap a cover to play that book,
    /// tap the title for the whole section as a list. Covers start as a
    /// placeholder and are filled in as they load (cache first).
    private func shelfItem(
        title: String,
        books: [Audiobook],
        showProgress: Bool,
        onSelect: @escaping (Audiobook) -> Void,
        onOpen: @escaping (String, [Audiobook]) -> Void
    ) -> CPListImageRowItem {
        let shown = Array(books.prefix(CPMaximumNumberOfGridImages))
        let size: CGSize
        if #available(iOS 26.0, *) {
            size = CPListImageRowItemRowElement.maximumImageSize
        } else {
            size = CPListImageRowItem.maximumImageSize
        }
        let placeholder = Self.placeholderCover(size: size)

        let item: CPListImageRowItem
        let setCover: (Int, UIImage) -> Void
        if #available(iOS 26.0, *) {
            let elements = shown.map {
                CPListImageRowItemRowElement(image: placeholder, title: $0.title, subtitle: Self.shelfSubtitle($0))
            }
            let row = CPListImageRowItem(text: title, elements: elements, allowsMultipleLines: false)
            item = row
            setCover = { [weak row] index, image in
                elements[index].image = image
                row?.elements = elements
            }
        } else {
            var images = Array(repeating: placeholder, count: shown.count)
            let row: CPListImageRowItem
            if #available(iOS 17.4, *) {
                row = CPListImageRowItem(text: title, images: images, imageTitles: shown.map(\.title))
            } else {
                row = CPListImageRowItem(text: title, images: images)
            }
            item = row
            setCover = { [weak row] index, image in
                images[index] = image
                row?.update(images)
            }
        }

        item.listImageRowHandler = { _, index, completion in
            if shown.indices.contains(index) { onSelect(shown[index]) }
            completion()
        }
        item.handler = { _, completion in
            onOpen(title, books)
            completion()
        }

        for (index, book) in shown.enumerated() {
            let progress = showProgress ? Self.progressFraction(book) : nil
            coverLoader.load(audiobookId: book.id, width: CoverURL.shelfCoverWidth, api: api) { image in
                guard let image else { return }
                setCover(index, Self.shelfCover(image, size: size, progress: progress))
            }
        }
        return item
    }

    /// "4h 12m left" for a book in progress, else its author.
    private static func shelfSubtitle(_ book: Audiobook) -> String? {
        if let progress = book.progress, let duration = book.duration, duration > 0, progress.position > 0 {
            return "\(formatDuration(max(0, duration - progress.position))) left"
        }
        return book.author
    }

    private static func progressFraction(_ book: Audiobook) -> Double? {
        guard let progress = book.progress, let duration = book.duration, duration > 0, progress.position > 0 else {
            return nil
        }
        return min(1, max(0, Double(progress.position) / Double(duration)))
    }

    /// A blank cover until the real one loads, so the row has its shape at once.
    private static func placeholderCover(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.22, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6).fill()
            if let symbol = UIImage(systemName: "book.closed")?.withTintColor(UIColor(white: 0.55, alpha: 1), renderingMode: .alwaysOriginal) {
                let side = min(size.width, size.height) * 0.4
                symbol.draw(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
            }
        }
    }

    /// The cover filling the row's square (centred, cropped), with the book's
    /// progress as a bar along the bottom -- the phone's Continue Listening
    /// cards show the same bar.
    private static func shelfCover(_ image: UIImage, size: CGSize, progress: Double?) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                width: drawn.width, height: drawn.height
            ))
            guard let progress else { return }
            let inset = size.width * 0.08
            let height = max(3, size.height * 0.045)
            let track = CGRect(x: inset, y: size.height - inset - height, width: size.width - inset * 2, height: height)
            UIColor(white: 0, alpha: 0.55).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: height / 2).fill()
            UIColor.white.setFill()
            var filled = track
            filled.size.width = max(height, track.width * progress)
            UIBezierPath(roundedRect: filled, cornerRadius: height / 2).fill()
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
        // bookSections shows at most 100; without a limit the server sends 50.
        bookSections(try await api.getAudiobooks(limit: 100), onSelect: onSelect)
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
