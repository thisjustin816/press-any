import EmulatorDomain
import Foundation

public protocol ToolchainDetector: Sendable {
    var identifier: String { get }
    func supports(_ system: GameSystem) -> Bool
    func detect(image: Data) -> ToolchainDetectionReport
}

public struct ToolchainDetectorRegistry: Sendable {
    public let detectors: [any ToolchainDetector]

    public init(detectors: [any ToolchainDetector]) {
        self.detectors = detectors
    }

    public static let standard = ToolchainDetectorRegistry(detectors: [GBToolsIDDetector()])

    /// Runs every detector that supports `system`, in registration order.
    public func detect(image: Data, system: GameSystem) -> [ToolchainDetectionReport] {
        detectors.filter { $0.supports(system) }.map { $0.detect(image: image) }
    }
}
