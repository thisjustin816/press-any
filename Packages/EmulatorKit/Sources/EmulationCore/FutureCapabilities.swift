import Foundation

// Capabilities a core may offer later. No core implements them yet, and the app checks for one
// with a cast (`core as? RewindCapability`), so a core without it needs nothing. The contracts
// below are filled in when each feature is built, so they don't commit to one core's API.

/// A core that can step back through recent frames.
public protocol RewindCapability: AnyObject {
    /// Keeps up to `seconds` of history within `memoryBudgetBytes`. Zero seconds turns it off.
    func configureRewind(seconds: Double, memoryBudgetBytes: Int)
    /// Records the state after the frame just run.
    func pushRewindFrame() throws
    /// Steps back one recorded frame. Returns false when there's no history left.
    func rewindFrame() throws -> Bool
}

/// A core that can apply cheat codes. Its contract is defined with the v1 cheat manager.
public protocol CheatCapability: AnyObject {}

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
