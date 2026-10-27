import Foundation

/// One completed PRINT command. Margins are measured in eight-pixel feed rows.
public struct PrinterOutput: Equatable, Sendable {
    public static let width = 160
    public let height: Int
    public let luminance: Data
    public let topMargin: Int
    public let bottomMargin: Int
    public let exposure: UInt8

    public enum ValidationError: Error { case invalidOutput }

    public init(height: Int, luminance: Data, topMargin: Int, bottomMargin: Int, exposure: UInt8) throws {
        guard (1...200).contains(height), luminance.count == Self.width * height,
              (0...15).contains(topMargin), (0...15).contains(bottomMargin), exposure <= 127 else {
            throw ValidationError.invalidOutput
        }
        self.height = height
        self.luminance = luminance
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.exposure = exposure
    }
}

public protocol PrinterCapability: AnyObject {
    var printerConnected: Bool { get }
    /// Call between frames on the core worker. Changing attachment clears pending output.
    func setPrinterConnected(_ connected: Bool)
    /// Completed commands in print order. A full host queue must be reported to the caller.
    func drainPrinterOutput() throws -> [PrinterOutput]
}
