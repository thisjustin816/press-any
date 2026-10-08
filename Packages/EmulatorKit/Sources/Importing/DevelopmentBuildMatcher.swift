import EmulatorDomain
import Foundation

public enum DevelopmentBuildMatcher {
    public enum Confidence: Equatable, Sendable { case medium, high }

    public struct Candidate: Equatable, Sendable {
        public let gameID: UUID
        public let score: Int
        public let confidence: Confidence
        public let reasons: [String]
    }

    public struct ArrivingSignals: Sendable {
        public let fingerprint: ImageFingerprint
        public let filenameMetadata: FilenameMetadata
        public let reports: [ToolchainDetectionReport]

        public init(fingerprint: ImageFingerprint, filenameMetadata: FilenameMetadata, reports: [ToolchainDetectionReport] = []) {
            self.fingerprint = fingerprint
            self.filenameMetadata = filenameMetadata
            self.reports = reports
        }
    }

    public struct BuildSignals: Sendable {
        public let fingerprint: ImageFingerprint?
        public let reports: [ToolchainDetectionReport]

        public init(fingerprint: ImageFingerprint?, reports: [ToolchainDetectionReport] = []) {
            self.fingerprint = fingerprint
            self.reports = reports
        }
    }

    public struct GameSignals: Sendable {
        public let game: Game
        public let builds: [BuildSignals]

        public init(game: Game, builds: [BuildSignals]) {
            self.game = game
            self.builds = builds
        }
    }

    // Two points require at least two additional supporting signals (or a strong signal) over
    // the runner-up. A single common hardware detail cannot decide the destination.
    public static let highConfidenceMargin = 2
    private static let strongWeight = 4
    private static let genericHeaders: Set<String> = [
        "game", "mygame", "newgame", "untitled", "test", "demo", "gbstudio", "gbdk", "gameboy", "gameboycolor",
    ]

    public static func isDistinctiveHeader(_ title: String) -> Bool {
        let key = GameMatcher.normalized(title)
        return key.count >= 3 && !genericHeaders.contains(key)
    }

    /// Games contain only imported Builds. Known dumps and duplicates bypass this matcher in
    /// the analyzer so release-family evidence retains precedence.
    public static func match(arriving: ArrivingSignals, games: [GameSignals]) -> [Candidate] {
        var headerOwners: [String: Set<UUID>] = [:]
        var bankOwners: [UInt64: Set<UUID>] = [:]
        for game in games {
            for build in game.builds {
                guard let fingerprint = build.fingerprint else { continue }
                headerOwners[GameMatcher.normalized(fingerprint.headerTitle), default: []].insert(game.game.id)
                for hash in fingerprint.bankHashes { bankOwners[hash, default: []].insert(game.game.id) }
            }
        }
        // A bank already in two Games is engine or library code, such as GB Studio's engine banks,
        // which unrelated games built with one version share byte for byte. It says nothing about
        // which project a ROM belongs to.
        let commonBanks = Set(bankOwners.filter { $0.value.count > 1 }.keys)
        let incoming = arriving.fingerprint
        let headerKey = GameMatcher.normalized(incoming.headerTitle)
        let usableHeader = isDistinctiveHeader(incoming.headerTitle) && (headerOwners[headerKey]?.count ?? 0) <= 1
        let titleKeys = Set(([arriving.filenameMetadata.suggestedTitle,
                              arriving.filenameMetadata.buildMetadata.baseTitle ?? ""]
            + (usableHeader ? [incoming.headerTitle] : []))
            .map(GameMatcher.normalized).filter { !$0.isEmpty })
        let banks = Set(incoming.bankHashes).subtracting(commonBanks)
        let incomingTools = Tools(arriving.reports)
        var scored: [(candidate: Candidate, qualifiesHigh: Bool)] = []
        for entry in games {
            let images = entry.builds.compactMap(\.fingerprint)
            let tools = entry.builds.map { Tools($0.reports) }
            let colorConflict = !entry.builds.isEmpty && images.count == entry.builds.count && (
                isDMGOnly(incoming.cgbFlag) && images.allSatisfy { $0.cgbFlag == 0xc0 }
                || incoming.cgbFlag == 0xc0 && images.allSatisfy { isDMGOnly($0.cgbFlag) }
            )
            let toolConflict = tools.contains {
                !incomingTools.highFamilies.isEmpty && !$0.highFamilies.isEmpty
                    && incomingTools.highFamilies != $0.highFamilies
            }
            guard !colorConflict, !toolConflict else { continue }
            var strong: [String] = []
            var supporting: [String] = []
            if isDistinctiveHeader(incoming.headerTitle), headerOwners[headerKey] == Set([entry.game.id]) {
                strong.append("same header title")
            }
            if ([entry.game.primaryTitle] + entry.game.aliases).contains(where: { titleKeys.contains(GameMatcher.normalized($0)) }) {
                strong.append("title or alias matches")
            }
            let sharedFraction = images.filter { $0.bankSize == incoming.bankSize }.map { image in
                let other = Set(image.bankHashes).subtracting(commonBanks)
                let smaller = min(banks.count, other.count)
                return smaller == 0 ? 0 : Double(banks.intersection(other).count) / Double(smaller)
            }.max() ?? 0
            let bankReason = "\(Int((sharedFraction * 100).rounded()))% of ROM banks shared"
            // Games from one engine share its banks until a second Game makes them common, so with
            // a shared engine, bank evidence only supports.
            let sameEngine = tools.contains { !$0.engineKeys.isDisjoint(with: incomingTools.engineKeys) }
            let banksSupport = sharedFraction >= 0.25 && (sharedFraction < 0.5 || sameEngine)
            if sharedFraction >= 0.5 && !sameEngine { strong.append(bankReason) }
            else if banksSupport { supporting.append(bankReason) }
            if images.contains(where: { $0.cartridgeType == incoming.cartridgeType && $0.ramSizeCode == incoming.ramSizeCode }) {
                supporting.append("same cartridge and RAM")
            }
            if images.contains(where: { $0.cgbFlag == incoming.cgbFlag }) { supporting.append("same color support") }
            if let matchingTools = tools.first(where: { incomingTools.matches($0) }), let family = matchingTools.familyName {
                let engine = matchingTools.engineNames.sorted().first
                supporting.append("both \(family)\(engine.map { " with \($0)" } ?? "")")
            }
            guard !strong.isEmpty || (banksSupport && supporting.count >= 3) else { continue }
            let candidate = Candidate(gameID: entry.game.id, score: strong.count * strongWeight + supporting.count,
                confidence: .medium, reasons: strong + supporting)
            scored.append((candidate, strong.count >= 2 || (strong.count == 1 && supporting.count >= 2)))
        }
        scored.sort {
            if $0.candidate.score != $1.candidate.score { return $0.candidate.score > $1.candidate.score }
            return $0.candidate.gameID.uuidString < $1.candidate.gameID.uuidString
        }
        guard let first = scored.first else { return [] }
        if scored.count > 1 && first.candidate.score == scored[1].candidate.score { return [] }
        let clearLead = scored.count == 1 || first.candidate.score - scored[1].candidate.score >= highConfidenceMargin
        return scored.enumerated().map { index, value in
            Candidate(gameID: value.candidate.gameID, score: value.candidate.score,
                confidence: index == 0 && value.qualifiesHigh && clearLead ? .high : .medium,
                reasons: value.candidate.reasons)
        }
    }

    private static func isDMGOnly(_ flag: UInt8) -> Bool { flag != 0x80 && flag != 0xc0 }

    private struct Tools {
        let families: Set<String>
        let highFamilies: Set<String>
        let engineNames: Set<String>
        let engineKeys: Set<String>
        let familyName: String?

        init(_ reports: [ToolchainDetectionReport]) {
            let components = reports.flatMap(\.components)
            let detected = components.filter { $0.kind == .toolchain }
            families = Set(detected.map { GameMatcher.normalized($0.name) })
            highFamilies = Set(detected.filter { $0.confidence == .high }.map { GameMatcher.normalized($0.name) })
            engineNames = Set(components.filter { $0.kind == .engine }.map(\.name))
            engineKeys = Set(engineNames.map(GameMatcher.normalized))
            familyName = detected.map(\.name).sorted().first
        }

        func matches(_ other: Tools) -> Bool {
            !families.isEmpty && families == other.families
                && Set(engineNames.map(GameMatcher.normalized)) == Set(other.engineNames.map(GameMatcher.normalized))
        }
    }
}
