import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSearchTemplateDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var contentProvider: CarPlayContentProvider?
    private var nowPlayingManager: CarPlayNowPlayingManager?

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
        self.interfaceController = nil
        self.contentProvider = nil
        self.nowPlayingManager = nil
    }

    // MARK: - Tab Bar Setup

    /// Present the tab bar immediately, then fill Home in when the network answers.
    ///
    /// This used to await four sequential API calls before calling
    /// setRootTemplate. CarPlay terminates an app that has not set a root
    /// template shortly after connecting, so in a car -- phone on cellular,
    /// server on the home LAN -- the screen stayed blank until the watchdog
    /// killed us. The root template now goes up synchronously and Home's
    /// sections arrive afterwards.
    @MainActor
    private func setupTabBar(interfaceController: CPInterfaceController) {
        guard let contentProvider = contentProvider else { return }

        let homeTemplate = CPListTemplate(title: "Home", sections: [])
        homeTemplate.tabImage = UIImage(systemName: "house")

        let libraryTemplate = contentProvider.libraryTemplate(
            onSearch: { [weak self] in self?.showSearch() },
            onAuthors: { [weak self] in self?.showAuthors() },
            onSeries: { [weak self] in self?.showSeries() },
            onCollections: { [weak self] in self?.showCollections() },
            onAllBooks: { [weak self] in self?.showAllBooks() }
        )
        libraryTemplate.tabImage = UIImage(systemName: "books.vertical")

        // Two tabs only. A CPSearchTemplate here is not a valid tab for an
        // audio app; it made this call fail, and with a nil completion handler
        // CarPlay throws rather than reporting the failure.
        let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: true) { success, error in
            if !success {
                print("CarPlay: setRootTemplate failed: \(String(describing: error))")
            }
        }

        Task { @MainActor [weak self] in
            let sections = await contentProvider.homeSections { [weak self] book in
                self?.playBook(book)
            }
            guard self != nil else { return }
            homeTemplate.updateSections(sections)
        }
    }

    /// Push the search template. Pushing is a supported presentation for
    /// CPSearchTemplate, unlike placing it in a tab bar.
    @MainActor
    private func showSearch() {
        guard let interfaceController = interfaceController else { return }
        let searchTemplate = CPSearchTemplate()
        searchTemplate.delegate = self
        interfaceController.pushTemplate(searchTemplate, animated: true) { success, error in
            if !success {
                print("CarPlay: pushTemplate(search) failed: \(String(describing: error))")
            }
        }
    }

    // MARK: - CPSearchTemplateDelegate

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        guard let contentProvider = contentProvider else {
            completionHandler([])
            return
        }
        Task { @MainActor in
            let items = await contentProvider.searchResults(for: searchText) { [weak self] book in
                self?.playBook(book)
            }
            completionHandler(items)
        }
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        // The item's own handler already starts playback; it is installed by
        // listItem(for:onSelect:) when the results are built.
        item.handler?(item, completionHandler) ?? completionHandler()
    }

    // MARK: - Playback

    private func playBook(_ book: Audiobook) {
        guard let audioPlayer = ServiceLocator.shared.audioPlayer,
              let api = ServiceLocator.shared.api else { return }

        Task { @MainActor in
            // Fetch fresh audiobook data from server to get latest progress
            // (user may have listened on another device since app launched)
            let freshBook: Audiobook
            do {
                freshBook = try await api.getAudiobook(id: book.id)
            } catch {
                // Fall back to cached data if server is unreachable
                freshBook = book
            }

            await audioPlayer.play(audiobook: freshBook)

            // Show Now Playing
            if let interfaceController = interfaceController,
               let nowPlayingManager = nowPlayingManager {
                interfaceController.pushTemplate(nowPlayingManager.template, animated: true, completion: nil)
            }
        }
    }

    // MARK: - Library Navigation

    private func showAuthors() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.authorsListTemplate { [weak self] author in
                self?.showBooksForAuthor(author)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showSeries() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.seriesListTemplate { [weak self] series in
                self?.showBooksForSeries(series)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showCollections() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.collectionsListTemplate { [weak self] collection in
                self?.showBooksForCollection(collection)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showAllBooks() {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.allBooksTemplate { [weak self] book in
                self?.playBook(book)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForAuthor(_ author: String) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.booksForAuthor(author) { [weak self] book in
                self?.playBook(book)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForSeries(_ series: String) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.booksForSeries(series) { [weak self] book in
                self?.playBook(book)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForCollection(_ collection: Collection) {
        guard let contentProvider = contentProvider else { return }
        Task { @MainActor in
            let template = await contentProvider.booksForCollection(collection) { [weak self] book in
                self?.playBook(book)
            }
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }
}
