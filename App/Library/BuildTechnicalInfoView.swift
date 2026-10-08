import EmulatorDomain
import GameIdentity
import SwiftUI

/// A Build's exact identity and what it was made with. Opening it detects the image again, so a
/// Build imported before detection, or under older signatures, shows current findings.
struct BuildTechnicalInfoView: View {
    @State private var build: Build
    let container: AppContainer

    init(build: Build, container: AppContainer) {
        _build = State(initialValue: build)
        self.container = container
    }

    @State private var reports: [ToolchainDetectionReport]?
    @State private var errorMessage: String?
    @State private var patchItems: [PatchRecipeItem] = []
    @State private var patchStepsError: String?
    @State private var patchFilenames: [UUID: String] = [:]
    @State private var variableMaps: [BuildVariableMap] = []
    @Environment(\.dismiss) private var dismiss

    /// How the image compares with No-Intro's data; a patched Build follows its bases.
    private var verification: String {
        let builds = container.repositories.builds
        let result = container.knownDumps?.verification(
            of: build,
            sha1: { $0.imageSHA1 },
            lookup: { try? builds.fetchBuild(id: $0) }
        )
        switch result {
        case .verified(let dump): return "Verified · \(dump.name)"
        case .badDump(let dump): return "Bad Dump · \(dump.name)"
        case .modified(let dump): return "Modified · patched from \(dump.name)"
        case .unknown, nil: return "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Build") {
                    LabeledContent("Name", value: build.displayName)
                    LabeledContent("System", value: build.system.displayName)
                    LabeledContent("Source", value: build.sourceKind == .patchRecipe ? "Patched" : "Imported")
                    LabeledContent("Added", value: build.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let region = build.region { LabeledContent("Region", value: region) }
                    if let language = build.language { LabeledContent("Language", value: language) }
                    if let revision = build.revision { LabeledContent("Revision", value: revision) }
                    if let version = build.versionString { LabeledContent("Version", value: version) }
                    if let baseTitle = build.baseTitle { LabeledContent("Base Title", value: baseTitle) }
                    if let hackTitle = build.hackTitle { LabeledContent("Hack Title", value: hackTitle) }
                    if let author = build.author { LabeledContent("Author", value: author) }
                    if let translation = build.translation { LabeledContent("Translation", value: translation) }
                    if let status = build.status { LabeledContent("Status", value: status) }
                    if let pin = build.corePin {
                        LabeledContent("Core", value: "\(pin.descriptor.identifier) \(pin.descriptor.version)")
                    }
                    LabeledContent("No-Intro", value: verification)
                    SHA256Row(hash: build.imageSHA256)
                    NavigationLink("Metadata Details") {
                        MetadataDetailsView(buildID: build.id, container: container)
                    }
                }

                if build.sourceKind == .patchRecipe {
                    if let patchStepsError {
                        Section("Patch Steps") {
                            Text(patchStepsError)
                                .foregroundStyle(.red)
                        }
                    }
                    ForEach(patchItems, id: \.position) { item in
                        Section("Patch Step \(item.position + 1)") {
                            LabeledContent("File", value: patchFilenames[item.patchAssetID] ?? "Missing patch")
                            LabeledContent("Status", value: item.enabled ? "Enabled" : "Disabled")
                            if let hash = item.expectedInputSHA256 {
                                SHA256Row(hash: hash, title: "Expected Input SHA-256")
                            } else {
                                LabeledContent("Expected Input SHA-256", value: "Not recorded")
                            }
                        }
                    }
                }

                if let reports {
                    ToolchainSection(reports: reports)
                } else if let errorMessage {
                    Section("Made With") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } else {
                    Section("Made With") {
                        ProgressView()
                    }
                }

                if !variableMaps.isEmpty {
                    Section("Variable Maps") {
                        ForEach(variableMaps) { map in
                            LabeledContent(map.originalFilename, value: Self.name(of: map.format))
                        }
                    }
                }
            }
            .navigationTitle("Technical Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
                if let updated = try? container.repositories.builds.fetchBuild(id: build.id) { build = updated }
            }
        }
    }

    private static func name(of format: BuildVariableMap.Format) -> String {
        switch format {
        case .gbStudioGlobals: "GB Studio globals"
        case .symbolFile: "Symbol file"
        }
    }

    private func refresh() async {
        if build.sourceKind == .patchRecipe {
            do {
                let recipe = try container.repositories.patchRecipes.fetchPatchRecipe(resultBuildID: build.id)
                patchItems = (recipe?.items ?? []).sorted { $0.position < $1.position }
                for item in patchItems {
                    if let asset = try container.repositories.assets.fetchAsset(id: item.patchAssetID) {
                        patchFilenames[item.patchAssetID] = asset.originalFilename
                            ?? URL(fileURLWithPath: asset.relativePath).lastPathComponent
                    }
                }
            } catch {
                patchStepsError = "Could not read the patch recipe: \(error.localizedDescription)"
            }
        }
        variableMaps = (try? container.repositories.variableMaps.fetchVariableMaps(buildID: build.id)) ?? []
        let refresh = container.toolchainRefresh
        let build = build
        do {
            reports = try await Task.detached { try refresh.execute(build: build) }.value
        } catch {
            errorMessage = "Could not read the Build’s image: \(error.localizedDescription)"
        }
    }
}
