import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didConnect called")
        self.interfaceController = interfaceController

        let item = CPListItem(text: "Sappho", detailText: "CarPlay is working!")
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Sappho", sections: [section])
        interfaceController.setRootTemplate(template, animated: true, completion: { success, error in
            print("[CarPlay] setRootTemplate completed, success: \(success), error: \(String(describing: error))")
        })
        print("[CarPlay] didConnect finished")
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didDisconnect called")
        self.interfaceController = nil
    }
}
