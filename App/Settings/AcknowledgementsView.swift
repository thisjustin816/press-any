import SwiftUI

/// The licenses of the open-source code that ships in the app, which their terms ask to be shown.
/// The texts are bundled verbatim from `App/Acknowledgements/`.
struct AcknowledgementsView: View {
    fileprivate struct Component: Identifiable {
        let name: String
        let use: String
        let licenseFile: String
        var id: String { name }
    }

    private let components = [
        Component(
            name: "SameBoy",
            use: "Game Boy and Game Boy Color emulation, and the boot ROMs",
            licenseFile: "SameBoy-LICENSE"
        ),
        Component(name: "GRDB.swift", use: "The game library’s database", licenseFile: "GRDB-LICENSE"),
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
        guard let url = Bundle.main.url(forResource: component.licenseFile, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "This build is missing the license text." }
        return text
    }
}
