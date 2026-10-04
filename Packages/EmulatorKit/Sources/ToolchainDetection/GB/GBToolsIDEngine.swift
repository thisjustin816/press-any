// Port of gbtoolsid's src/gbtoolchainid.c and src/entries.c at the revision in GBToolsIDData.
// Names follow the C source so the two can be read side by side.

import EmulatorDomain
import Foundation

struct GBToolsIDPattern: Sendable {
    let name: String
    /// The bytes C's sizeof() covers, so string patterns include their terminator.
    let bytes: [UInt8]
}

struct GBToolsIDMaskedPattern: Sendable {
    let name: String
    let bytes: [UInt8]
    /// 0 means ignore the byte at that position; anything else means it must match.
    let mask: [UInt8]
}

final class GBToolsIDEngine {
    enum EntryType: Int {
        case tools = 0
        case engine = 1
        case music = 2
        case soundfx = 3

        var componentKind: ToolchainComponentKind {
            switch self {
            case .tools: .toolchain
            case .engine: .engine
            case .music: .musicDriver
            case .soundfx: .soundEffectsDriver
            }
        }
    }

    struct Entry {
        let type: EntryType
        let name: String
        let version: String
        let evidence: [ToolchainEvidence]
    }

    /// FORMAT_ENTRY's result: what entry_add and entry_add_with_version receive.
    struct EntryTemplate {
        let type: EntryType
        let name: String
        let version: String
    }

    // gbtoolsid's TOOL_ENTRY_COUNT_MAX.
    private static let entryCountMax = 50

    private let searchBuffer: [UInt8]
    private(set) var addrLastMatch = 0
    private(set) var entries: [Entry] = []
    /// Matches since the current check began or since its last entry_add.
    private var pendingEvidence: [ToolchainEvidence] = []

    init(image: [UInt8]) {
        searchBuffer = image
    }

    // MARK: gbtools_detect

    func detect(strictMode: Bool) {
        // GB Studio's entry_check_match relies on the GBDK check running first.
        let resultGBDK = check(checkGBDK)

        if !strictMode || resultGBDK {
            check(checkZGB)
            check(checkCrossZGB)
            // GBBasic first, so its entries are not mislabeled as GB Studio.
            if !check(checkGBBasic) {
                check(checkGBStudio)
            }
        }

        check(checkTurboRascal)
        check(checkGBForth)
        check(checkGBNim)
        check(checkGBSDK)
        check(checkMatlabGB)
        check(checkLLVMGBLibGBXX)

        check(checkMusic)
        check(checkSoundFX)
    }

    @discardableResult
    private func check(_ body: () -> Bool) -> Bool {
        pendingEvidence = []
        return body()
    }

    @discardableResult
    private func check(_ body: () -> Void) -> Bool {
        pendingEvidence = []
        body()
        return true
    }

    // MARK: Pattern primitives

    /// check_pattern_addr: the pattern must sit exactly at `matchIndex`.
    func checkPatternAtAddr(_ pattern: GBToolsIDPattern, _ matchIndex: Int) -> Bool {
        let bytes = pattern.bytes
        guard !searchBuffer.isEmpty, !bytes.isEmpty else { return false }
        guard matchIndex >= 0, matchIndex + bytes.count <= searchBuffer.count else { return false }
        let equal = searchBuffer.withUnsafeBytes { haystack in
            bytes.withUnsafeBytes { memcmp(haystack.baseAddress! + matchIndex, $0.baseAddress!, bytes.count) == 0 }
        }
        guard equal else { return false }
        addrLastMatch = matchIndex
        pendingEvidence.append(ToolchainEvidence(signature: pattern.name, offset: matchIndex))
        return true
    }

    /// FIND_PATTERN_BUF: find_pattern over the whole sizeof() of the pattern.
    func findPatternBuf(_ pattern: GBToolsIDPattern) -> Bool {
        findPattern(pattern.bytes, name: pattern.name)
    }

    /// FIND_PATTERN_STR_NOTERM: find_pattern over sizeof() - 1, which drops the last byte
    /// whether or not the pattern is a string.
    func findPatternStrNoTerm(_ pattern: GBToolsIDPattern) -> Bool {
        findPattern(Array(pattern.bytes.dropLast()), name: pattern.name)
    }

    /// FIND_PATTERN_BUF_MASKED: find_pattern_masked. As in gbtoolsid without DEBUG_LOG_MATCHES,
    /// a masked match does not update addrLastMatch.
    func findPatternBufMasked(_ pattern: GBToolsIDMaskedPattern) -> Bool {
        guard !searchBuffer.isEmpty, !pattern.bytes.isEmpty, pattern.bytes.count <= searchBuffer.count else {
            return false
        }
        // Drop leading bytes that the mask ignores.
        guard let start = pattern.mask.firstIndex(where: { $0 != 0 }) else { return false }
        let bytes = Array(pattern.bytes[start...])
        let mask = Array(pattern.mask[start...])

        let found = firstIndex(of: bytes) { haystack, index in
            for offset in 1..<bytes.count where mask[offset] != 0 && bytes[offset] != haystack[index + offset] {
                return false
            }
            return true
        }
        guard let found else { return false }
        pendingEvidence.append(ToolchainEvidence(signature: pattern.name, offset: found))
        return true
    }

    /// find_pattern: first occurrence anywhere in the image.
    private func findPattern(_ bytes: [UInt8], name: String) -> Bool {
        guard !searchBuffer.isEmpty, !bytes.isEmpty, bytes.count <= searchBuffer.count else { return false }
        let found = bytes.withUnsafeBytes { needle in
            firstIndex(of: bytes) { haystack, index in
                memcmp(haystack.baseAddress! + index, needle.baseAddress!, bytes.count) == 0
            }
        }
        guard let found else { return false }
        addrLastMatch = found
        pendingEvidence.append(ToolchainEvidence(signature: name, offset: found))
        return true
    }

    /// The first index where `bytes[0]` occurs and `matches` accepts the candidate, scanning
    /// candidates with memchr as gbtoolsid does. `bytes` must be non-empty.
    private func firstIndex(of bytes: [UInt8], where matches: (UnsafeRawBufferPointer, Int) -> Bool) -> Int? {
        searchBuffer.withUnsafeBytes { haystack in
            let lastStart = haystack.count - bytes.count
            var start = 0
            while start <= lastStart {
                guard let hit = memchr(haystack.baseAddress! + start, Int32(bytes[0]), lastStart - start + 1) else {
                    return nil
                }
                let index = haystack.baseAddress!.distance(to: UnsafeRawPointer(hit))
                if matches(haystack, index) {
                    return index
                }
                start = index + 1
            }
            return nil
        }
    }

    /// check_pattern_addr against raw bytes, for the few patterns gbtoolsid declares inline in a
    /// check function rather than with the DEF_* macros.
    func checkPatternAtAddr(_ bytes: [UInt8], name: String, _ matchIndex: Int) -> Bool {
        checkPatternAtAddr(GBToolsIDPattern(name: name, bytes: bytes), matchIndex)
    }

    func getAddrLastMatch() -> Int {
        addrLastMatch
    }

    // MARK: entries.c

    func formatEntry(_ type: EntryType, _ name: String, _ version: String) -> EntryTemplate {
        EntryTemplate(type: type, name: name, version: version)
    }

    func entryAdd(_ template: EntryTemplate) {
        entryAdd(template, version: template.version)
    }

    func entryAddWithVersion(_ template: EntryTemplate, _ version: String) {
        entryAdd(template, version: version)
    }

    private func entryAdd(_ template: EntryTemplate, version: String) {
        guard entries.count < Self.entryCountMax else { return }
        entries.append(Entry(type: template.type, name: template.name, version: version, evidence: pendingEvidence))
        pendingEvidence = []
    }

    /// entry_check_match: a nil version matches any version, as a NULL argument does in C.
    func entryCheckMatch(_ type: EntryType, _ name: String, _ version: String?) -> Bool {
        entries.contains { entry in
            entry.type == type && entry.name == name && (version == nil || entry.version == version)
        }
    }
}
