import Foundation

/// The emoji the badge picker offers, in groups. `SetSaveProfileBadge` still checks every badge, so
/// this list only limits what the picker shows. It leaves out emoji newer than the oldest iOS the
/// app supports, which would draw as an empty box, and any emoji built from several people.
public enum SaveProfileBadgeCatalog {
    public struct Group: Sendable, Equatable, Identifiable {
        public let title: String
        public let emoji: [String]

        public var id: String { title }
    }

    // An emoji drawn from a text-style character is written with its variation selector (U+FE0F),
    // spelled out here because editors drop it from a pasted emoji.
    public static let groups: [Group] = [
        Group(title: "Faces", emoji: [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🙂", "😉", "😊", "😍", "😎",
            "🤩", "🥳", "😴", "🤔", "😬", "😱", "🥶", "🤯", "😈", "👻", "💀", "🤖",
        ]),
        Group(title: "Animals", emoji: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮",
            "🐷", "🐸", "🐵", "🐔", "🐧", "🦉", "🦄", "🐝", "🦋", "🐢", "🐙", "🐬",
            "🐳", "🦖", "🐉",
        ]),
        Group(title: "Food", emoji: [
            "🍎", "🍌", "🍇", "🍓", "🍒", "🍑", "🍍", "🥝", "🍅", "🥑", "🌽", "🥕",
            "🍔", "🍟", "🍕", "🌮", "🍣", "🍩", "🍪", "🎂", "🍦", "🍫", "☕", "🍺",
        ]),
        Group(title: "Games and Sports", emoji: [
            "🎮", "\u{1F579}\u{FE0F}", "🎲", "🧩", "🎯", "🎳", "⚽", "🏀", "🏈", "⚾",
            "🎾", "🏐", "🏆", "🥇", "🎸", "🎹", "🥁", "🎤", "🎧", "🎬",
        ]),
        Group(title: "Nature and Weather", emoji: [
            "🌞", "🌙", "⭐", "🌈", "⚡", "🔥", "💧", "\u{2744}\u{FE0F}", "🌊", "🌸", "🌻",
            "🌲", "🍀", "🍄", "🌵", "🌋",
        ]),
        Group(title: "Objects", emoji: [
            "🚀", "🛸", "🚗", "\u{2708}\u{FE0F}", "🚂", "⛵", "🏠", "🏰", "\u{1F5E1}\u{FE0F}",
            "\u{1F6E1}\u{FE0F}", "🔑", "💎", "💰", "🎁", "📱", "💾", "📷", "🔔", "💡", "🔮",
        ]),
        Group(title: "Symbols", emoji: [
            "\u{2764}\u{FE0F}", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💯", "✅",
            "❌", "❓", "❗", "💤", "💥", "💫", "✨", "🎵", "🚩", "🏁",
        ]),
    ]
}
