import SwiftUI

@main
@MainActor
struct PressAnyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: bootstrap)
        }
    }
}
