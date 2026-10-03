import SwiftUI

@main
@MainActor
struct PressAnyApp: App {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: bootstrap)
        }
    }
}
