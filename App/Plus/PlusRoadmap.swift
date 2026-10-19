import Foundation

/// Features on the Plus screen. The roadmap follows docs/product.md,
/// excluding crash reporting and usage counts.
enum PlusRoadmap {
    struct Item: Identifiable, Equatable {
        let title: String
        let detail: String
        var id: String { title }
    }

    static let includedToday = [
        Item(title: "LCD Filters", detail: "LCD 1× adds a subtle pixel grid, and LCD 3× red, green and blue subpixels."),
        Item(title: "App Icons", detail: "The home-screen icon in Berry, Grape, Teal, Kiwi or Dandelion."),
        Item(title: "Auto State History", detail: "Keep 3, 5 or 10 Auto States for each save. Without Plus, the latest is kept."),
        Item(title: "Timed States", detail: "An Auto State every 1, 2, 5 or 10 minutes of play. Pausing restarts the interval."),
        Item(title: "Model", detail: "Run Game Boy and Game Boy Color games on a Game Boy, Game Boy Pocket, Super Game Boy, Game Boy Color, Game Boy Advance or Game Boy Player, with Super Game Boy colors."),
    ]

    static let upcoming = [
        Item(title: "iCloud Sync", detail: "Saves, states, settings and library details on all your devices. ROMs stay on each device."),
        Item(title: "Community Catalog", detail: "Game details, expected hashes and patch links from a shared catalog and other sources. Never ROMs."),
        Item(title: "Tags and Collections", detail: "Group and filter the library your own way."),
        Item(title: "More Imports", detail: "7z archives, and a game with its saves, patches, artwork and manuals in one step."),
        Item(title: "Artwork and Documents", detail: "Multiple artwork images, regional covers, and manuals and guides that open over a paused game."),
        Item(title: "Rewind", detail: "Step back from a few seconds to a few minutes."),
        Item(title: "Slow Motion", detail: "Play at a quarter, half or three quarters of full speed."),
        Item(title: "Frame Advance", detail: "Move a game on one frame at a time, with a frame counter."),
        Item(title: "Quick Actions", detail: "Save, load, rewind and more from the game menu, controller buttons and skins."),
        Item(title: "Super Game Boy Borders", detail: "The border a Super Game Boy game draws around the picture."),
        Item(title: "Shaders", detail: "A small, tested set of screen effects, chosen with the community."),
        Item(title: "Layout Editor and Skins", detail: "Move and resize the screen and controls, and import Delta and Manic skins."),
        Item(title: "Capture Gallery and Notes", detail: "Screenshots kept with each Build, and timestamped gameplay notes."),
        Item(title: "External Displays", detail: "Play on an AirPlay or wired display, with the phone as the controller."),
        Item(title: "Developer Mode", detail: "Memory search and editing, watches and other tools for making and testing games."),
    ]

    /// Planned, but not part of what Plus promises: whether it's free or Plus isn't decided.
    static let alsoPlanned = [
        Item(title: "Game Boy Advance", detail: "Playing Game Boy Advance games is planned for a later version, with no date yet."),
    ]
}
