import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var contentProvider: CarPlayContentProvider?
    private var nowPlayingManager: CarPlayNowPlayingManager?
    private var homeTemplate: CPListTemplate?
    private var homeListener: UUID?
    private var homeRebuildScheduled = false
    private var lastKnownConnected = NetworkMonitor.shared.isConnected

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        guard let api = ServiceLocator.shared.api,
              let audioPlayer = ServiceLocator.shared.audioPlayer else {
            // Services not ready yet — show placeholder
            let item = CPListItem(text: "Sappho", detailText: "Loading...")
            let section = CPListSection(items: [item])
            let template = CPListTemplate(title: "Sappho", sections: [section])
            interfaceController.setRootTemplate(template, animated: false) { success, error in
                if !success {
                    print("CarPlay: placeholder setRootTemplate failed: \(String(describing: error))")
                }
            }
            return
        }

        contentProvider = CarPlayContentProvider(api: api)
        nowPlayingManager = CarPlayNowPlayingManager(audioPlayer: audioPlayer)

        setupTabBar(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        if let homeListener {
            MainActor.assumeIsolated { HomeFeedStore.shared.removeListener(homeListener) }
        }
        self.homeListener = nil
        self.homeTemplate = nil
        self.interfaceController = nil
        self.contentProvider = nil
        self.nowPlayingManager = nil
    }

    // MARK: - Tab Bar Setup

    /// Present the tab bar immediately with Home built from what is already on
    /// the device, then refresh Home section by section.
    ///
    /// CarPlay terminates an app that has not set a root template shortly
    /// after connecting, so the root goes up synchronously. Home used to start
    /// empty and wait for four sequential requests (60 s timeout each) before
    /// showing anything; on a slow link that was minutes of a blank screen.
    /// Now it opens with the saved feed, the current book and the downloads,
    /// and each section is replaced the moment its own request answers (12 s
    /// deadline each). A slow or failed section never holds up the rest.
    @MainActor
    private func setupTabBar(interfaceController: CPInterfaceController) {
        guard let contentProvider = contentProvider else { return }

        let store = HomeFeedStore.shared
        store.activate(account: ServiceLocator.shared.api?.accountKey)

        let homeTemplate = CPListTemplate(title: "Home", sections: [])
        homeTemplate.tabImage = UIImage(systemName: "house")
        self.homeTemplate = homeTemplate
        rebuildHome()

        let libraryTemplate = contentProvider.libraryTemplate(
            onDownloaded: { [weak self] in self?.showDownloaded() },
            onAuthors: { [weak self] in self?.showAuthors() },
            onSeries: { [weak self] in self?.showSeries() },
            onCollections: { [weak self] in self?.showCollections() },
            onAllBooks: { [weak self] in self?.showAllBooks() }
        )
        libraryTemplate.tabImage = UIImage(systemName: "books.vertical")

        // Two tabs only. CPSearchTemplate is a navigation-app template; an
        // audio app may not show it at all (as a tab or pushed), so there is
        // no search in CarPlay.
        let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: true) { success, error in
            if !success {
                print("CarPlay: setRootTemplate failed: \(String(describing: error))")
            }
        }

        // Rebuild Home whenever a section lands (coalesced: four sections
        // answering together cause one rebuild, not four).
        homeListener = store.addListener { [weak self] _ in
            self?.scheduleHomeRebuild()
        }

        // With the phone locked the SwiftUI scene may never run, so restore
        // the last-played book here too (it is idempotent); it fills Resume.
        if let audioPlayer = ServiceLocator.shared.audioPlayer, audioPlayer.currentAudiobook == nil {
            Task { @MainActor [weak self] in
                await audioPlayer.restoreLastPlayed()
                self?.scheduleHomeRebuild()
            }
        }

        observeHomeInputs()
        refreshHome()
    }

    /// Rebuild Home when something it shows changes outside the feed: the
    /// connection (back online: refresh; gone: downloads first) or the book
    /// in the player (Resume row).
    @MainActor
    private func observeHomeInputs() {
        withObservationTracking {
            _ = NetworkMonitor.shared.isConnected
            _ = ServiceLocator.shared.audioPlayer?.currentAudiobook?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.homeTemplate != nil else { return }
                let wasOnline = self.lastKnownConnected
                self.lastKnownConnected = NetworkMonitor.shared.isConnected
                if self.lastKnownConnected && !wasOnline {
                    self.refreshHome()
                }
                self.scheduleHomeRebuild()
                self.observeHomeInputs()
            }
        }
    }

    @MainActor
    private func refreshHome() {
        guard let api = ServiceLocator.shared.api else { return }
        let store = HomeFeedStore.shared
        store.activate(account: api.accountKey)
        guard NetworkMonitor.shared.isConnected else {
            rebuildHome()
            return
        }
        Task { @MainActor in
            await store.refresh(fetch: HomeFeedStore.apiFetcher(api))
        }
    }

    @MainActor
    private func scheduleHomeRebuild() {
        guard !homeRebuildScheduled else { return }
        homeRebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.homeRebuildScheduled = false
            self.rebuildHome()
        }
    }

    @MainActor
    private func rebuildHome() {
        guard let homeTemplate, let contentProvider else { return }
        let sections = contentProvider.homeSections(
            store: HomeFeedStore.shared,
            onSelect: { [weak self] book in self?.playBook(book) },
            onRetry: { [weak self] in self?.refreshHome() }
        )
        homeTemplate.updateSections(sections)
    }

    // MARK: - Playback

    /// Start the tapped book at once and show Now Playing.
    ///
    /// This used to fetch the book from the server first (to pick up progress
    /// from other devices), on the default 60 s timeout. On a slow link that
    /// was up to a minute of nothing after a tap, even for a downloaded book.
    /// Now nothing waits on the network: the book starts from the newer of its
    /// row's server position and this device's saved one (a downloaded book
    /// from its local file), and the server's copy is fetched afterwards.
    @MainActor
    private func playBook(_ book: Audiobook) {
        guard let audioPlayer = ServiceLocator.shared.audioPlayer else { return }
        CarPlayPlaybackStarter.start(
            book,
            downloaded: DownloadManager.shared.cachedMeta[book.id]?.toAudiobook(),
            player: audioPlayer,
            showNowPlaying: { showNowPlaying() }
        )
    }

    /// Show Now Playing without pushing it twice. A second tap on a book (or
    /// a second play request) while it is already on the stack pushed the
    /// same template again, which CarPlay rejects with an exception.
    @MainActor
    private func showNowPlaying() {
        guard let interfaceController, let nowPlayingManager else { return }
        let template = nowPlayingManager.template
        if interfaceController.topTemplate === template { return }
        if interfaceController.templates.contains(where: { $0 === template }) {
            interfaceController.pop(to: template, animated: true) { success, error in
                if !success {
                    print("CarPlay: pop to Now Playing failed: \(String(describing: error))")
                }
            }
            return
        }
        interfaceController.pushTemplate(template, animated: true) { success, error in
            if !success {
                print("CarPlay: push Now Playing failed: \(String(describing: error))")
            }
        }
    }

    // MARK: - Library Navigation

    private func showDownloaded() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = contentProvider.downloadedTemplate { [weak self] book in
                self?.playBook(book)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    /// Push a server-backed list at once with a "Loading…" row and fill it in
    /// when the request answers. A list that takes longer than `timeout`, or
    /// fails, shows a row saying so with a retry, rather than leaving the tap
    /// apparently ignored (the push used to wait for the request).
    @MainActor
    private func pushList(title: String, load: @escaping () async throws -> [CPListSection]) {
        let loading = CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)])
        let template = CPListTemplate(title: title, sections: [loading])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        fill(template, load: load)
    }

    @MainActor
    private func fill(_ template: CPListTemplate, load: @escaping () async throws -> [CPListSection]) {
        Task { @MainActor [weak self, weak template] in
            let sections: [CPListSection]
            do {
                let loaded = try await Deadline.run(seconds: Self.listTimeout) { try await load() }
                sections = loaded.contains { !$0.items.isEmpty }
                    ? loaded
                    : [CPListSection(items: [CPListItem(text: "Nothing here", detailText: nil)])]
            } catch {
                let retry = CPListItem(text: "Couldn't load", detailText: "Check your connection. Tap to retry.")
                retry.handler = { [weak self, weak template] _, completion in
                    if let self, let template {
                        template.updateSections([CPListSection(items: [CPListItem(text: "Loading…", detailText: nil)])])
                        self.fill(template, load: load)
                    }
                    completion()
                }
                sections = [CPListSection(items: [retry])]
            }
            guard self != nil, let template else { return }
            template.updateSections(sections)
        }
    }

    private static let listTimeout: TimeInterval = 15

    private func showAuthors() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: "Authors") {
                try await contentProvider.authorsSections { [weak self] author in
                    self?.showBooksForAuthor(author)
                }
            }
        }
    }

    private func showSeries() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: "Series") {
                try await contentProvider.seriesSections { [weak self] series in
                    self?.showBooksForSeries(series)
                }
            }
        }
    }

    private func showCollections() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: "Collections") {
                try await contentProvider.collectionsSections { [weak self] collection in
                    self?.showBooksForCollection(collection)
                }
            }
        }
    }

    private func showAllBooks() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: "All Books") {
                try await contentProvider.allBooksSections { [weak self] book in
                    self?.playBook(book)
                }
            }
        }
    }

    private func showBooksForAuthor(_ author: String) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: author) {
                try await contentProvider.booksForAuthorSections(author) { [weak self] book in
                    self?.playBook(book)
                }
            }
        }
    }

    private func showBooksForSeries(_ series: String) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: series) {
                try await contentProvider.booksForSeriesSections(series) { [weak self] book in
                    self?.playBook(book)
                }
            }
        }
    }

    private func showBooksForCollection(_ collection: Collection) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            self.pushList(title: collection.name) {
                try await contentProvider.booksForCollectionSections(collection) { [weak self] book in
                    self?.playBook(book)
                }
            }
        }
    }
}
