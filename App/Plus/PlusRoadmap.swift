import Foundation

/// What Plus holds today and what's coming, as the Plus screen lists it. The upcoming list follows
/// the v1.1 scope paragraph in docs/product.md, without its non-features, and changes with it.
enum PlusRoadmap {
    struct Item: Identifiable, Equatable {
        let title: String
        let detail: String
        var id: String { title }
    }

    static let includedToday = [
        Item(title: "LCD Filters", detail: "LCD 1× adds a subtle pixel grid, and LCD 3× red, green and blue subpixels."),
    ]

    static let upcoming = [
        Item(title: "iCloud Sync", detail: "Saves, states, settings and library details on all your devices. ROMs stay on each device."),
        Item(title: "Community Catalog", detail: "Game details, expected hashes and patch links from a shared catalog and other sources. Never ROMs."),
        Item(title: "Tags and Collections", detail: "Group and filter the library your own way."),
        Item(title: "More Imports", detail: "7z archives, and a game with its saves, patches, artwork and manuals in one step."),
        Item(title: "Artwork and Documents", detail: "Artwork found on import, and manuals and guides that open over a paused game."),
        Item(title: "Rewind", detail: "Step back from a few seconds to a few minutes."),
        Item(title: "Slow Motion", detail: "Play at a quarter, half or three quarters of full speed."),
        Item(title: "Frame Advance", detail: "Move a game on one frame at a time, with a frame counter."),
        Item(title: "Quick Actions", detail: "Save, load, rewind and more from the game menu, controller buttons and skins."),
        Item(title: "Model Override", detail: "Run a game as a Game Boy, Game Boy Color or Super Game Boy, with Super Game Boy palettes and borders."),
        Item(title: "Shaders", detail: "A small, tested set of screen effects, chosen with the community."),
        Item(title: "Layout Editor and Skins", detail: "Move and resize the screen and controls, and import Delta and Manic skins."),
        Item(title: "Screenshots and Notes", detail: "Captures and timestamped notes kept with each Build."),
        Item(title: "External Displays", detail: "Play on an AirPlay or wired display, with the phone as the controller."),
        Item(title: "Developer Mode", detail: "Memory search and editing, watches and other tools for making and testing games."),
    ]
}
