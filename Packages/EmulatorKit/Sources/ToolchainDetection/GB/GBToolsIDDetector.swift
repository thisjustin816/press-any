import EmulatorDomain
import Foundation

/// Game Boy toolchain, engine and audio-driver detection ported from gbtoolsid
/// (https://github.com/bbbbbr/gbtoolsid), which is in the public domain. The port runs in
/// process; it never spawns the gbtoolsid command-line tool.
public struct GBToolsIDDetector: ToolchainDetector {
    public static let identifier = "gbtoolsid"
    /// Bump when the Swift port changes behavior without a new upstream revision.
    public static let portVersion = "1"

    /// gbtoolsid's `-s` option: test for ZGB, GB Studio and GBBasic only after GBDK matched.
    public let strictMode: Bool

    public init(strictMode: Bool = false) {
        self.strictMode = strictMode
    }

    public var identifier: String { Self.identifier }

    public func supports(_ system: GameSystem) -> Bool {
        switch system {
        case .gameBoy, .gameBoyColor: true
        }
    }

    public func detect(image: Data) -> ToolchainDetectionReport {
        let engine = GBToolsIDEngine(image: [UInt8](image))
        engine.detect(strictMode: strictMode)
        return ToolchainDetectionReport(
            detector: Self.identifier,
            detectorVersion: Self.portVersion,
            corpusRevision: GBToolsIDData.upstreamRevision,
            components: engine.entries.map { entry in
                DetectedToolchainComponent(
                    kind: entry.type.componentKind,
                    name: entry.name,
                    version: entry.version.isEmpty ? nil : entry.version,
                    evidence: entry.evidence
                )
            }
        )
    }
}
