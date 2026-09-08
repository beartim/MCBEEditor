import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Keep the shared Documents/Textures directory available from the first
        // launch so iTunes File Sharing and the Files app can be used without
        // any additional in-app setup.
        BlockTextureOverrideStore.prepareSharedDirectoryAndReload()

        // Segmented controls are especially prone to ellipsizing on 4.7–6.1"
        // iPhones. Use a slightly smaller title there while preserving the
        // existing iPad typography.
        if UIDevice.current.userInterfaceIdiom == .phone {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .regular)
            ]
            let selectedAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
            UISegmentedControl.appearance().setTitleTextAttributes(attributes, for: .normal)
            UISegmentedControl.appearance().setTitleTextAttributes(selectedAttributes, for: .selected)
        }
        return true
    }



    func applicationDidBecomeActive(_ application: UIApplication) {
        // Users may replace PNGs through Files while the app is backgrounded.
        // Reload here as well; render caches include the override revision so a
        // subsequent map render immediately uses the changed colours.
        BlockTextureOverrideStore.prepareSharedDirectoryAndReload()
    }
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
