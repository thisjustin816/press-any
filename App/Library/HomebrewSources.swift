import Foundation

/// Where the empty library points a player who has no game yet. Both open in the browser, so the
/// app downloads nothing itself and the games stay the sites' own.
enum HomebrewSources {
    /// gbdev's catalog of freely distributable Game Boy homebrew.
    static let homebrewHub = URL(string: "https://hh.gbdev.io/")!
    /// itch.io's Game Boy ROM tag.
    static let itch = URL(string: "https://itch.io/games/tag-gameboy-rom")!
}
