import Foundation

/// The Game Boy Color games that unlock something on a Game Boy Advance, which Automatic plays on
/// one. A game learns it's on a Game Boy Advance only from a register its boot ROM leaves, read by
/// its own startup code, so nothing in the header says so and the games are listed instead, by
/// every No-Intro release of each, matched by SHA-1. Each of them also brightens its own colors
/// there, for that darker screen.
///
/// - Wendy: Every Witch Way opens Advance World, three more levels.
/// - Shantae says "GBA Enhanced!" on its title screen and sells a Tinkerbat transformation.
/// - The Legend of Zelda: Oracle of Seasons and Oracle of Ages open the Advance Shop.
///
/// A Build also counts when it's patched from one, in a Game whose Base is one, or a hack matched
/// to one (`includes(_:lookup:gameBuilds:)`).
public enum GameBoyAdvanceFeatures {
    /// One release, as No-Intro's Game Boy Color data names it.
    public struct Release: Equatable, Sendable {
        public let name: String
        /// The image's SHA-1, lowercase, as No-Intro lists it.
        public let sha1: String

        public init(name: String, sha1: String) {
            self.name = name
            self.sha1 = sha1.lowercased()
        }
    }

    /// Every cartridge release, from No-Intro's Game Boy Color data. Shantae's beta and the two
    /// images No-Intro took from its later re-release on another console aren't cartridge
    /// releases and are left out.
    public static let releases: [Release] = [
        Release(name: "Wendy - Every Witch Way (USA, Europe)", sha1: "8ca45ed882c23df714bda46b227a857deddc899f"),
        Release(name: "Shantae (USA)", sha1: "520e48c50f6e997fcd841ca368fc9abc1dbddec1"),
        Release(name: "Shantae (World) (Limited Run Games)", sha1: "71bc428f2746df2a2c6238e14f594d3e5c8da131"),
        Release(name: "Legend of Zelda, The - Oracle of Seasons (Europe) (En,Fr,De,Es,It)", sha1: "360b9408e569ba826212eac1ebea1b09573cb48c"),
        Release(name: "Legend of Zelda, The - Oracle of Seasons (USA, Australia)", sha1: "ba1268290fb2b1b70505d2d7b5825fc8a4816a4b"),
        Release(name: "Zelda no Densetsu - Fushigi no Kinomi - Daichi no Shou (Japan)", sha1: "08bf49d7e225c695f64d38131cb720decb84b663"),
        Release(name: "Legend of Zelda, The - Oracle of Ages (Europe) (En,Fr,De,Es,It)", sha1: "9f2dff3c46406839f839a8d535353dfc1e3e8670"),
        Release(name: "Legend of Zelda, The - Oracle of Ages (USA, Australia)", sha1: "880374fb978b18af4aa529e2e32f7ffb4d7dd2f4"),
        Release(name: "Zelda no Densetsu - Fushigi no Kinomi - Jikuu no Shou (Japan)", sha1: "596aa066ccee9fae71643576f7526baa22d26d6d"),
    ]

    private static let sha1s = Set(releases.map(\.sha1))
    private static let names = Set(releases.map(\.name))

    /// Whether the image with this SHA-1 is a listed release.
    public static func lists(sha1: String) -> Bool {
        sha1s.contains(sha1.lowercased())
    }

    /// Whether `build` is one of these games: its own image is a listed release; it was imported
    /// patched from one, which its base game names (`BaseGameReference.releaseName`, set when the
    /// player matches the hack to a No-Intro release); the Build its patch was made from is one,
    /// following patches back to the start; or its Game's Base Build is one. `lookup` finds a Build
    /// by ID and `gameBuilds` a Game's Builds. A Build with the same title and nothing that ties it
    /// to a listed release isn't one.
    public static func includes(_ build: Build, lookup: (UUID) -> Build?, gameBuilds: (UUID) -> [Build]) -> Bool {
        // Each Build is asked once, which ends a chain that loops back on itself.
        var asked = Set<UUID>()
        func isListed(_ build: Build) -> Bool {
            guard asked.insert(build.id).inserted else { return false }
            if build.imageSHA1.map(lists(sha1:)) == true { return true }
            if let reference = build.baseGameReference, reference.system == .gameBoyColor,
               let name = reference.releaseName, names.contains(name) {
                return true
            }
            if build.sourceKind == .patchRecipe, let parent = build.parentBuildID.flatMap(lookup), isListed(parent) {
                return true
            }
            guard let base = gameBuilds(build.gameID).first(where: { $0.isBase && $0.id != build.id }) else {
                return false
            }
            return isListed(base)
        }
        return isListed(build)
    }
}
