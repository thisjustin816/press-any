import Foundation

// Capabilities a core may offer beyond EmulatorCore. The app checks for one with a cast
// (`core as? RewindCapability`), so a core without it needs nothing. SameBoy implements cheats; no
// core implements the others yet. Rewind's contract follows the spec, and the rest get theirs
// when their feature is built, so none commits to one core's API.

/// A core that can step back through recent frames.
public protocol RewindCapability: AnyObject {
    /// Keeps up to `seconds` of history within `memoryBudgetBytes`. Zero seconds turns it off.
    func configureRewind(seconds: Double, memoryBudgetBytes: Int)
    /// Records the state after the frame just run.
    func pushRewindFrame() throws
    /// Steps back one recorded frame. Returns false when there's no history left.
    func rewindFrame() throws -> Bool
}

/// A core that can apply Game Genie and GameShark cheat codes. Codes stay through a reset, a
/// state load and a new image, and only change when the set is replaced.
public protocol CheatCapability: AnyObject {
    /// Replaces every active code with these. If the core can't read one of them, it throws and
    /// keeps the codes it had.
    func setCheatCodes(_ codes: [String]) throws
    /// Turns the active codes on or off as a whole, keeping them.
    func setCheatsEnabled(_ enabled: Bool)
    /// Whether the core reads `code`, without applying it. Works before any image is loaded.
    func isValidCheatCode(_ code: String) -> Bool
}

/// A core whose memory can be read and written. Its contract is defined with v1 memory search.
public protocol MemoryAccessCapability: AnyObject {}

/// A core with a cartridge real-time clock the app can set. Its contract is defined in v1.
public protocol RTCCapability: AnyObject {}

/// A core that can connect to another over a link cable.
public protocol LinkCableCapability: AnyObject {}

/// A core that can emulate the Game Boy Camera.
public protocol CameraCapability: AnyObject {}

/// A core that can emulate the Game Boy Printer.
public protocol PrinterCapability: AnyObject {}
