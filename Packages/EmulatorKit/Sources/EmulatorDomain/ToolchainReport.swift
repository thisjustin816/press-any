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

/// How strongly a component is indicated, from how many of its own signatures matched. It rates
/// the match, not the version label, which can be a range either way.
public enum ToolchainConfidence: String, Codable, Hashable, Sendable {
    /// Nothing of its own matched; another component's match implies it.
    case low
    /// One signature matched.
    case medium
    /// Two or more signatures matched.
    case high
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

    public var confidence: ToolchainConfidence {
        switch evidence.count {
        case 0: .low
        case 1: .medium
        default: .high
        }
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
