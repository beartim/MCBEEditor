import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
