import SwiftUI

/// The open-source code that ships in the app. Licenses whose terms ask to be shown are bundled
/// verbatim from `App/Acknowledgements/`; public-domain code gets a credit instead.
struct AcknowledgementsView: View {
    fileprivate struct Component: Identifiable {
        enum License {
            case bundled(file: String)
            case publicDomain(credit: String)
        }

        let name: String
        let use: String
        let license: License
        var id: String { name }
    }

    private let components = [
        Component(
            name: "SameBoy",
            use: "Game Boy and Game Boy Color emulation, and the boot ROMs",
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
    ]

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
        case .publicDomain(let credit):
            return credit
        case .bundled(let file):
            guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return "This build is missing the license text." }
            return text
        }
    }
}
