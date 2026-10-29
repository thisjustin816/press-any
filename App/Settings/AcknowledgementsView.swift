import GameIdentity
import SwiftUI

/// Third-party code, artwork, data and online sources, with credits and licenses.
struct AcknowledgementsView: View {
    fileprivate struct Component: Identifiable {
        enum License {
            case bundled(file: String)
            case publicDomain(credit: String)
            case freeData(credit: String)
            case rightsNotice(credit: String)
        }

        let name: String
        let use: String
        let license: License
        var id: String { name }
    }

    private let components: [Component] = [
        Component(
            name: "Wood Table",
            use: """
            Printer background photograph by Dimitrios Savva, from Poly Haven.
            Source: https://polyhaven.com/a/wood_table
            License: CC0 1.0 Universal (public domain).
            """,
            license: .bundled(file: "PrinterWood-CC0")
        ),
        Component(
            name: "SameBoy",
            use: """
            Game Boy, Super Game Boy, Game Boy Color and Game Boy Advance emulation, boot ROMs and
            boot palettes by Lior Halphon.
            Source: https://github.com/LIJI32/SameBoy
            """,
            license: .bundled(file: "SameBoy-LICENSE")
        ),
        Component(name: "GRDB.swift", use: "The game library’s database", license: .bundled(file: "GRDB-LICENSE")),
        Component(
            name: "Corporatus",
            use: """
            Wordmark lettering by Alex Rosario and Roc Mitchell.
            Source: https://asr.me/font/corp.html
            License: Desktop license for static artwork; the font file is not bundled.
            """,
            license: .bundled(file: "Corporatus-LICENSE")
        ),
        Component(
            name: "gbtoolsid",
            use: "Detecting which tools a game was made with",
            license: .publicDomain(credit: """
            gbtoolsid by bbbbbr (https://github.com/bbbbbr/gbtoolsid) is in the public domain under \
            the Unlicense (https://unlicense.org). \(AppBrand.displayName)’s toolchain detection is a \
            Swift port of its detection logic and signature tables.
            """)
        ),
        Component(
            name: "libretro LCD shaders",
            use: "The idea behind the LCD 1× and LCD 3× display filters",
            license: .publicDomain(credit: """
            \(AppBrand.displayName)’s LCD 1× and LCD 3× filters are its own shader code, modelled \
            on the LCD shaders in libretro’s slang-shaders collection for RetroArch \
            (https://github.com/libretro/slang-shaders), among them lcd3x by Gigaherz, which is in \
            the public domain. No shader code was copied from them. They are credited here anyway.
            """)
        ),
        Component(
            name: "Game Boy Printer disassembly",
            use: "How the Game Boy Printer behaves",
            license: .rightsNotice(credit: """
            Raphaël Boichot’s Game-Boy-Printer-disassembly \
            (https://github.com/Raphael-Boichot/Game-Boy-Printer-disassembly) documents the protocol \
            the printer’s firmware implements and runs that firmware in an emulator. \
            \(AppBrand.displayName)’s printer is its own code, built from that documentation and \
            checked against the emulator. No code from the project is included.
            """)
        ),
        Component(
            name: "No-Intro",
            use: "Recognizing known Game Boy and Game Boy Color releases",
            license: .freeData(credit: AcknowledgementsView.noIntroCredit)
        ),
        Component(
            name: "Libretro thumbnails",
            use: "Optional online box art for recognized games",
            license: .rightsNotice(credit: """
            Source: https://github.com/libretro-thumbnails/libretro-thumbnails
            Service: https://thumbnails.libretro.com

            Credits: the Libretro thumbnail community's scanners, collectors and contributors.
            Upstream also credits MobyGames and Fandom as sources.

            \(LibretroArtworkProvider.rights)

            No game artwork is bundled in \(AppBrand.displayName). Selected downloads are kept \
            in your local library with their source URL and rights notice.
            """)
        ),
    ]

    /// The data's source and date, read from the bundled file so a refresh updates it.
    private static var noIntroCredit: String {
        let systems = (try? KnownDumpIndex.bundled())?.catalog.systems ?? []
        let versions = systems.map { "\($0.dat) \($0.version) (\($0.games) games)" }.joined(separator: "\n")
        return """
        Game identification data from No-Intro’s DAT-o-MATIC (https://datomatic.no-intro.org):

        \(versions)

        DAT-o-MATIC’s Data Usage License lets the data be used, copied, modified and \
        distributed by anyone for any lawful purpose, without attribution. \(AppBrand.displayName) \
        credits it anyway. No-Intro is not affiliated with \(AppBrand.displayName).
        """
    }

    var body: some View {
        List(components) { component in
            NavigationLink {
                LicenseTextView(component: component)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.name)
                    Text(component.use)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollOverflowCue()
        .navigationTitle("Acknowledgements")
    }
}

private struct LicenseTextView: View {
    let component: AcknowledgementsView.Component

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .scrollOverflowCue()
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        switch component.license {
        case .publicDomain(let credit), .freeData(let credit), .rightsNotice(let credit):
            return credit
        case .bundled(let file):
            guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return "This build is missing the license text." }
            return text
        }
    }
}
