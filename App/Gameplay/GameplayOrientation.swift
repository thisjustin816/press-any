import GameplayInput
import UIKit

@MainActor
enum GameplayOrientation {
    private(set) static var supported: UIInterfaceOrientationMask = .portrait

    /// The library, sheets and Playtiles, which fits a portrait phone, stay portrait; otherwise
    /// the Orientation setting decides.
    static func mask(
        style: TouchControlStyle?,
        orientation: ScreenOrientation = .automatic,
        coveredBySheet: Bool
    ) -> UIInterfaceOrientationMask {
        guard style == .gameBoy, !coveredBySheet else { return .portrait }
        return switch orientation {
        case .automatic: [.portrait, .landscapeLeft, .landscapeRight]
        case .portrait: .portrait
        case .landscape: .landscape
        }
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
            // Allowing a direction leaves rotation to iOS, including its rotation lock. A direction
            // no longer allowed is left at once: a sheet or the library returns to portrait even
            // with the phone held sideways, and a game set to Landscape turns even when held upright.
            let current: UIInterfaceOrientationMask = switch scene.interfaceOrientation {
            case .landscapeLeft: .landscapeLeft
            case .landscapeRight: .landscapeRight
            case .portraitUpsideDown: .portraitUpsideDown
            default: .portrait
            }
            if !mask.contains(current) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
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
