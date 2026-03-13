import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var contentProvider: CarPlayContentProvider?
    private var nowPlayingManager: CarPlayNowPlayingManager?

    private var audioPlayer: AudioPlayerService? { ServiceLocator.shared.audioPlayer }
    private var api: SapphoAPI? { ServiceLocator.shared.api }
    private var authRepository: AuthRepository? { ServiceLocator.shared.authRepository }

    private var tabBarTemplate: CPTabBarTemplate?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        guard let api = api, let audioPlayer = audioPlayer else {
            showNotSignedIn(interfaceController: interfaceController)
            return
        }

        guard authRepository?.isAuthenticated == true else {
            showNotSignedIn(interfaceController: interfaceController)
            return
        }

        contentProvider = CarPlayContentProvider(api: api)
        nowPlayingManager = CarPlayNowPlayingManager(audioPlayer: audioPlayer)

        buildRootTemplate(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.contentProvider = nil
        self.nowPlayingManager = nil
        self.tabBarTemplate = nil
    }

    // MARK: - Root Template

    private func buildRootTemplate(interfaceController: CPInterfaceController) {
        guard let contentProvider = contentProvider else { return }

        // Home tab
        let homeTemplate = CPListTemplate(title: "Home", sections: [])
        homeTemplate.tabSystemItem = .featured
        homeTemplate.emptyViewTitleVariants = ["Loading..."]

        // Library tab
        let libraryTemplate = contentProvider.libraryTemplate(
            onAuthors: { [weak self] in self?.showAuthors() },
            onSeries: { [weak self] in self?.showSeries() },
            onCollections: { [weak self] in self?.showCollections() },
            onAllBooks: { [weak self] in self?.showAllBooks() }
        )
        libraryTemplate.tabSystemItem = .more
        libraryTemplate.tabTitle = "Library"
        if let libraryIcon = UIImage(systemName: "books.vertical") {
            libraryTemplate.tabImage = libraryIcon
        }

        // Reading List tab
        let readingListTemplate = CPListTemplate(title: "Reading List", sections: [])
        if let readingListIcon = UIImage(systemName: "heart.fill") {
            readingListTemplate.tabImage = readingListIcon
        }
        readingListTemplate.emptyViewTitleVariants = ["Loading..."]

        // Now Playing tab
        let nowPlayingTemplate = nowPlayingManager?.template ?? CPNowPlayingTemplate.shared
        // CPNowPlayingTemplate is automatically configured by the framework

        let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate, readingListTemplate, nowPlayingTemplate])
        self.tabBarTemplate = tabBar

        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)

        // Load content asynchronously
        loadHomeContent(into: homeTemplate)
        loadReadingListContent(into: readingListTemplate)
    }

    // MARK: - Not Signed In

    private func showNotSignedIn(interfaceController: CPInterfaceController) {
        let item = CPListItem(text: "Not signed in", detailText: "Open the Sappho app to sign in")
        item.isEnabled = false
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Sappho", sections: [section])
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Home Content

    private func loadHomeContent(into template: CPListTemplate) {
        guard let contentProvider = contentProvider else { return }

        Task {
            let homeTemplate = await contentProvider.homeTemplate { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                template.updateSections(homeTemplate.sections)
                template.emptyViewTitleVariants = ["No audiobooks"]
            }
        }
    }

    // MARK: - Reading List Content

    private func loadReadingListContent(into template: CPListTemplate) {
        guard let contentProvider = contentProvider else { return }

        Task {
            let readingListTemplate = await contentProvider.readingListTemplate { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                template.updateSections(readingListTemplate.sections)
                template.emptyViewTitleVariants = ["No books in reading list"]
            }
        }
    }

    // MARK: - Library Navigation

    private func showAuthors() {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: "Authors", sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.authorsListTemplate { [weak self] author in
                self?.showBooksForAuthor(author)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No authors"]
            }
        }
    }

    private func showSeries() {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: "Series", sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.seriesListTemplate { [weak self] series in
                self?.showBooksForSeries(series)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No series"]
            }
        }
    }

    private func showCollections() {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: "Collections", sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.collectionsListTemplate { [weak self] collection in
                self?.showBooksForCollection(collection)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No collections"]
            }
        }
    }

    private func showAllBooks() {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: "All Books", sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.allBooksTemplate { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No audiobooks"]
            }
        }
    }

    private func showBooksForAuthor(_ author: String) {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: author, sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.booksForAuthor(author) { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No audiobooks"]
            }
        }
    }

    private func showBooksForSeries(_ series: String) {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: series, sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.booksForSeries(series) { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No audiobooks"]
            }
        }
    }

    private func showBooksForCollection(_ collection: Collection) {
        guard let contentProvider = contentProvider, let interfaceController = interfaceController else { return }

        let loadingTemplate = CPListTemplate(title: collection.name, sections: [])
        loadingTemplate.emptyViewTitleVariants = ["Loading..."]
        interfaceController.pushTemplate(loadingTemplate, animated: true, completion: nil)

        Task {
            let template = await contentProvider.booksForCollection(collection) { [weak self] audiobook in
                self?.playAndShowNowPlaying(audiobook)
            }
            await MainActor.run {
                loadingTemplate.updateSections(template.sections)
                loadingTemplate.emptyViewTitleVariants = ["No audiobooks"]
            }
        }
    }

    // MARK: - Playback

    private func playAndShowNowPlaying(_ audiobook: Audiobook) {
        guard let audioPlayer = audioPlayer else { return }

        Task {
            await audioPlayer.play(audiobook: audiobook)
        }

        // Switch to Now Playing tab
        if let tabBar = tabBarTemplate {
            let templates = tabBar.templates
            if let nowPlayingTemplate = templates.last as? CPNowPlayingTemplate {
                tabBar.select(nowPlayingTemplate)
            }
        }
    }
}
