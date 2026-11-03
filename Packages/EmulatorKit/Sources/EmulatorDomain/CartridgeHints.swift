import Foundation

/// The cartridge header fields Automatic reads to choose the hardware a game runs on.
public struct CartridgeHints: Equatable, Sendable {
    /// 0x143. Bit 7 marks a game made for the Game Boy Color (0x80 or 0xC0).
    public let cgbFlag: UInt8
    /// 0x146. 0x03 marks a game that supports the Super Game Boy.
    public let sgbFlag: UInt8
    /// 0x14B. 0x33 means the publisher is in `newLicensee` instead.
    public let oldLicensee: UInt8
    /// 0x144 and 0x145 as two ASCII characters, such as "01" for Nintendo.
    public let newLicensee: String

    public init(cgbFlag: UInt8 = 0, sgbFlag: UInt8 = 0, oldLicensee: UInt8 = 0, newLicensee: String = "") {
        self.cgbFlag = cgbFlag
        self.sgbFlag = sgbFlag
        self.oldLicensee = oldLicensee
        self.newLicensee = newLicensee
    }

    /// The hints in `image`'s header, or nil when the image is too short to have one.
    public init?(image: Data) {
        guard image.count > 0x14B else { return nil }
        // Offsets count from the image's first byte, which is not index 0 when it is a slice.
        func byte(_ offset: Int) -> UInt8 { image[image.startIndex + offset] }
        self.init(
            cgbFlag: byte(0x143),
            sgbFlag: byte(0x146),
            oldLicensee: byte(0x14B),
            newLicensee: String(decoding: [byte(0x144), byte(0x145)], as: UTF8.self)
        )
    }

    public var isMadeForGameBoyColor: Bool { cgbFlag & 0x80 != 0 }

    /// The Super Game Boy itself ignores the SGB flag unless the old licensee is 0x33.
    public var supportsSuperGameBoy: Bool { sgbFlag == 0x03 && oldLicensee == 0x33 }

    public var isPublishedByNintendo: Bool {
        oldLicensee == 0x01 || (oldLicensee == 0x33 && newLicensee == "01")
    }

    /// What Automatic picks with Super Game Boy borders off, the default.
    public var automaticModel: HardwareModel { automaticModel(superGameBoyBorders: false) }

    /// The first match: a Game Boy Color game plays on a Game Boy Color, or with Super Game Boy
    /// borders on, one that also supports the Super Game Boy plays on a Game Boy Player, whose
    /// television look suits a border; a Super Game Boy game on a Super Game Boy 2, which runs at
    /// the Game Boy's own speed; a Nintendo game on a Game Boy Color, for the palette its boot ROM
    /// gives Nintendo's Game Boy games; anything else on a Game Boy Pocket.
    public func automaticModel(superGameBoyBorders: Bool) -> HardwareModel {
        if isMadeForGameBoyColor {
            return superGameBoyBorders && supportsSuperGameBoy ? .gameBoyPlayer : .gameBoyColor
        }
        if supportsSuperGameBoy { return .superGameBoy2 }
        if isPublishedByNintendo { return .gameBoyColor }
        return .gameBoyPocket
    }
}
