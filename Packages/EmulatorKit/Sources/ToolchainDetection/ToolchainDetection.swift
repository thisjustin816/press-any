import EmulatorDomain
import Foundation

/// What a detected component is. A ROM can carry several at once, for example GB Studio's engine
/// built with GBDK and playing music through hUGETracker.
public enum ToolchainComponentKind: String, Codable, Hashable, Sendable {
    case toolchain
    case engine
    case musicDriver
    case soundEffectsDriver
}

/// A signature that matched, and where. Offsets are byte offsets into the image.
public struct ToolchainEvidence: Codable, Hashable, Sendable {
    public let signature: String
    public let offset: Int

    public init(signature: String, offset: Int) {
        self.signature = signature
        self.offset = offset
    }
}

public struct DetectedToolchainComponent: Codable, Hashable, Sendable {
    public let kind: ToolchainComponentKind
    public let name: String
    /// The detector's version label as written, which may be one version, a range such as
    /// "2.0.18 - 2.1.5" or an open range such as "2020.4.3.0+". Nil when the detector names none.
    public let version: String?
    public let evidence: [ToolchainEvidence]

    public init(kind: ToolchainComponentKind, name: String, version: String?, evidence: [ToolchainEvidence]) {
        self.kind = kind
        self.name = name
        self.version = version
        self.evidence = evidence
    }
}

/// One detector's findings for one image. An empty `components` list means nothing was
/// recognized, which is a valid result rather than an error. Detection never identifies a Game
/// and never proves two Builds' saves compatible.
public struct ToolchainDetectionReport: Codable, Hashable, Sendable {
    public let detector: String
    public let detectorVersion: String
    /// The revision of the signature corpus the detector was built from.
    public let corpusRevision: String
    public let components: [DetectedToolchainComponent]

    public init(detector: String, detectorVersion: String, corpusRevision: String, components: [DetectedToolchainComponent]) {
        self.detector = detector
        self.detectorVersion = detectorVersion
        self.corpusRevision = corpusRevision
        self.components = components
    }

    public func components(of kind: ToolchainComponentKind) -> [DetectedToolchainComponent] {
        components.filter { $0.kind == kind }
    }
}

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
