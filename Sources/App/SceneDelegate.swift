import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let root = WorldListViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window

        let urls = connectionOptions.urlContexts.map { $0.url }
        if !urls.isEmpty {
            DispatchQueue.main.async { root.handleExternalURLs(urls) }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let urls = URLContexts.map { $0.url }
        guard !urls.isEmpty,
              let navigation = window?.rootViewController as? UINavigationController,
              let list = navigation.viewControllers.first as? WorldListViewController else { return }
        if navigation.presentedViewController != nil {
            navigation.dismiss(animated: true) { list.handleExternalURLs(urls) }
        } else {
            list.handleExternalURLs(urls)
        }
    }
}
