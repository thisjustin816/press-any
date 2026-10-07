import EmulatorApplication
import Foundation

struct RiskyLaunch {
    let context: LaunchContext
    let assessment: SaveCompatibilityAssessment
    let profileName: String

    var canDeclareCompatibility: Bool {
        assessment.writtenBy?.gameID == context.gameID
    }

    var message: String {
        var lines = ["\"\(profileName)\" was last saved by \(assessment.writtenBy?.displayName ?? "another Build")."]
        for risk in assessment.risks {
            switch risk {
            case .declaredNonShare:
                lines.append("These Builds are declared not to share saves.")
            case .differentRegionOrLanguage(let writtenRegion, let playingRegion, let writtenLanguage, let playingLanguage):
                lines.append("This save was last written by the \(writtenRegion) release. This Build is the \(playingRegion) release.")
                if let writtenLanguage, let playingLanguage, writtenLanguage != playingLanguage {
                    lines.append("The save's language is \(writtenLanguage); this Build's is \(playingLanguage).")
                }
            case .gbStudio:
                lines.append("A GB Studio game can lay out its saved data differently from one Build to the next, even with the same GB Studio version.")
            case .differentTools(let writtenWith, let playingWith):
                lines.append("That Build was made with \(Self.list(writtenWith)); this one with \(Self.list(playingWith)).")
            case .differentSaveHardware:
                lines.append("The two Builds declare different save hardware in their cartridge headers.")
            }
        }
        lines.append("A copy keeps the original save safe.")
        return lines.joined(separator: "\n")
    }

    private static func list(_ tools: [String]) -> String {
        tools.isEmpty ? "unrecognized tools" : tools.formatted(.list(type: .and))
    }
}
