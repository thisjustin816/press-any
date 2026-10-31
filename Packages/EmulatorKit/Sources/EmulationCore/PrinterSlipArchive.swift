import Foundation

/// A slip as a file: each printed section's rows, margins and exposure, as the printer delivered
/// them. Rows keep their luminance bytes, so a later renderer or background still applies.
public enum PrinterSlipArchive {
    public enum ArchiveError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidRows
    }

    static let version = 1

    private struct File: Codable {
        let version: Int
        let sections: [Section]
    }

    private struct Section: Codable {
        let height: Int
        let topMargin: Int
        let bottomMargin: Int
        let exposure: UInt8
        /// One luminance byte per pixel, 160 to a row, in base64.
        let rows: Data
        /// Written only for a later copy of a command, as true.
        let followsCopy: Bool?
    }

    public static func encode(_ slip: PrinterSlip) throws -> Data {
        let file = File(version: version, sections: slip.sections.map {
            Section(height: $0.height, topMargin: $0.topMargin, bottomMargin: $0.bottomMargin,
                    exposure: $0.exposure, rows: $0.luminance, followsCopy: $0.followsCopy ? true : nil)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data, id: UUID) throws -> PrinterSlip {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == version else { throw ArchiveError.unsupportedVersion(file.version) }
        let sections = try file.sections.map { section in
            do {
                return try PrinterOutput(
                    height: section.height, luminance: section.rows, topMargin: section.topMargin,
                    bottomMargin: section.bottomMargin, exposure: section.exposure,
                    followsCopy: section.followsCopy ?? false
                )
            } catch {
                throw ArchiveError.invalidRows
            }
        }
        return try PrinterSlip(id: id, sections: sections)
    }
}
