import GameIdentity
import SwiftUI

/// The open-source code and data that ship in the app. Licenses whose terms ask to be shown are
/// bundled verbatim from `App/Acknowledgements/`; public-domain code and freely licensed data get
/// a credit instead.
struct AcknowledgementsView: View {
    fileprivate struct Component: Identifiable {
        enum License {
            case bundled(file: String)
            case publicDomain(credit: String)
            case freeData(credit: String)
        }

        let name: String
        let use: String
        let license: License
        var id: String { name }
    }

    private let components: [Component] = [
        Component(
            name: "SameBoy",
            use: """
            Game Boy and Game Boy Color emulation, boot ROMs and boot palettes by Lior Halphon.
            Source: https://github.com/LIJI32/SameBoy
            """,
            license: .bundled(file: "SameBoy-LICENSE")
        ),
        Component(name: "GRDB.swift", use: "The game library’s database", license: .bundled(file: "GRDB-LICENSE")),
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
            name: "No-Intro",
            use: "Recognizing known Game Boy and Game Boy Color releases",
            license: .freeData(credit: AcknowledgementsView.noIntroCredit)
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
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        switch component.license {
        case .publicDomain(let credit), .freeData(let credit):
            return credit
        case .bundled(let file):
            guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return "This build is missing the license text." }
            return text
        }
    }
}
