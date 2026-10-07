import GameplayInput
import UIKit

@MainActor
enum GameplayOrientation {
    private(set) static var supported: UIInterfaceOrientationMask = .portrait

    static func mask(style: TouchControlStyle?, coveredBySheet: Bool) -> UIInterfaceOrientationMask {
        style == .gameBoy && !coveredBySheet ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }

    static func update(_ mask: UIInterfaceOrientationMask) {
        guard supported != mask else { return }
        supported = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let root = scene.keyWindow?.rootViewController else { continue }
            root.setNeedsUpdateOfSupportedInterfaceOrientations()
            var presented = root
            while let next = presented.presentedViewController { presented = next }
            presented.setNeedsUpdateOfSupportedInterfaceOrientations()
            // Enabling landscape leaves rotation to iOS, including its rotation lock. A sheet or
            // the library must return to portrait even when the phone is still held sideways.
            if mask == .portrait, scene.interfaceOrientation.isLandscape {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        GameplayOrientation.supported
    }
}
