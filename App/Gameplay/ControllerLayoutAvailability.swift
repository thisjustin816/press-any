import GameplayInput
import UIKit

@MainActor
enum ControllerLayoutAvailability {
    static let unavailableMessage = "Playtiles requires a screen at least 68 mm wide. Game Boy controls are used on this iPhone."

    static var supportsPlaytiles: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.session.role == .windowApplication }) else { return false }
        let bounds = scene.screen.nativeBounds
        return TouchControlStyle.playtiles.isAvailable(
            nativeWidth: Double(bounds.width), nativeHeight: Double(bounds.height)
        )
    }

    static func isAvailable(_ style: TouchControlStyle) -> Bool {
        style != .playtiles || supportsPlaytiles
    }
}
