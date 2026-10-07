import Foundation
import SwiftUI

/// What the app is and how the library and Quick Play work, shown at first launch until a fuller
/// walkthrough exists, and from Settings at any time.
struct WelcomeView: View {
    /// Shown as Get Started at the bottom. Nil when Settings pushes this, where Back closes it.
    var onDone: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    WordmarkView(size: 34)
                        .accessibilityLabel(AppBrand.displayName)
                    Text("Every version, every save, one library.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ForEach(Self.topics) { topic in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.headline)
                            Text(topic.text)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: topic.symbol)
                            .font(.title2)
                            .foregroundStyle(Color(uiColor: AppBrand.Wordmark.accent))
                            .frame(width: 36)
                    }
                    .accessibilityElement(children: .combine)
                }

                if onDone != nil {
                    Text("Find this again in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            if let onDone {
                Button {
                    onDone()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityIdentifier("welcome.getStarted")
            }
        }
        .navigationTitle(onDone == nil ? "How \(AppBrand.displayName) Works" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Topic: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private static let topics = [
        Topic(
            symbol: "square.grid.2x2",
            title: "Your Library",
            text: "Tap + and Import File, or share a ROM, patch, save or zip to \(AppBrand.displayName) from Files or another app. The library keeps its own copy, so the original can be moved or deleted."
        ),
        Topic(
            symbol: "square.stack.3d.up",
            title: "Games and Builds",
            text: "Each game holds its Builds: versions, revisions and patched copies. Apply an IPS or BPS patch from a game’s page, or open it with Import File or the share sheet. The original Build stays as it was."
        ),
        Topic(
            symbol: "externaldrive",
            title: "Saves",
            text: "Each game keeps its saves in Save Profiles, written as you play. A .sav or .srm file you import becomes a new Save Profile. By default, a game opens again where you left off."
        ),
        Topic(
            symbol: "play.circle",
            title: "Quick Play",
            text: "Tap + and Quick Play ROM to play a file without adding it to the library. The session is kept for later under Quick Play Sessions, and Add to Library in the game menu adds it to the library."
        ),
        Topic(
            symbol: "gamecontroller",
            title: "In a Game",
            text: "Tap \(AppBrand.displayName) on the controller to pause and open the menu: Fast Forward, Save State and Load State, Settings, and Close Game. A Bluetooth controller's Menu button opens the same menu; press it again to close and resume. The touch controls hide while one is in use."
        ),
        Topic(
            symbol: "folder",
            title: "Exports",
            text: "Export ROM and Export Save on a game’s page put a copy in Files, in the \(AppBrand.displayName) folder."
        ),
        Topic(
            symbol: "hand.raised",
            title: "Bring Your Own Games",
            text: "\(AppBrand.displayName) comes with no games. Play homebrew, your own projects, or copies of cartridges you own."
        ),
    ]
}

/// When launch shows the welcome screen: once for each version of its content, and never in an
/// automated run, where it would cover the screen a test or screenshot expects.
enum WelcomeScreen {
    /// Raise this when the content changes enough that everyone should see it again.
    static let contentVersion = 2
    static let shownVersionKey = "welcome.shownVersion"

    /// An automated run also marks it shown, so a later launch the system starts on its own, such
    /// as one from the share sheet, doesn't show it either.
    static func showsAtLaunch(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let automated = environment["XCTestConfigurationFilePath"] != nil
            || defaults.string(forKey: "UITestLibrary") != nil
            || ScreenshotScene.current != nil
        if automated {
            markShown(defaults: defaults)
            return false
        }
        return defaults.integer(forKey: shownVersionKey) < contentVersion
    }

    static func markShown(defaults: UserDefaults = .standard) {
        defaults.set(contentVersion, forKey: shownVersionKey)
    }
}
