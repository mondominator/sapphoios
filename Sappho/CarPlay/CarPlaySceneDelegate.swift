import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

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
            interfaceController.setRootTemplate(template, animated: false, completion: nil)
            return
        }

        contentProvider = CarPlayContentProvider(api: api)
        nowPlayingManager = CarPlayNowPlayingManager(audioPlayer: audioPlayer)

        Task { @MainActor in
            await setupTabBar(interfaceController: interfaceController)
        }
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

    @MainActor
    private func setupTabBar(interfaceController: CPInterfaceController) async {
        guard let contentProvider = contentProvider else { return }

        let homeTemplate = await contentProvider.homeTemplate { [weak self] book in
            self?.playBook(book)
        }
        homeTemplate.tabImage = UIImage(systemName: "house")

        let libraryTemplate = contentProvider.libraryTemplate(
            onAuthors: { [weak self] in self?.showAuthors() },
            onSeries: { [weak self] in self?.showSeries() },
            onCollections: { [weak self] in self?.showCollections() },
            onAllBooks: { [weak self] in self?.showAllBooks() }
        )
        libraryTemplate.tabImage = UIImage(systemName: "books.vertical")

        let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    // MARK: - Playback

    private func playBook(_ book: Audiobook) {
        guard let audioPlayer = ServiceLocator.shared.audioPlayer else { return }

        Task { @MainActor in
            await audioPlayer.play(audiobook: book)

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
