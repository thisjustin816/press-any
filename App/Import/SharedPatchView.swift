import EmulatorDomain
import Importing
import Patching
import SwiftUI

struct SharedPatchView: View {
    let file: SharedFile
    let container: AppContainer
    let onFinished: () -> Void

    @State private var games: [Game] = []
    @State private var builds: [Build] = []
    @State private var gameID: UUID?
    @State private var buildID: UUID?
    @State private var displayName = ""
    /// The patch filename's naming, and the last suggestion shown, so choosing a Game can rename
    /// the Build to suit it without overwriting a name the player typed.
    @State private var naming: FilenameMetadata?
    @State private var suggestedBuildName = ""
    @State private var region = ""
    @State private var language = ""
    @State private var revision = ""
    @State private var version = ""
    @State private var baseTitle = ""
    @State private var hackTitle = ""
    @State private var author = ""
    @State private var translation = ""
    @State private var status = ""
    @State private var unknownGroups: [String] = []
    @State private var errorMessage: String?
    @State private var baseMismatchDetails = ""
    @State private var mismatchedBuild: Build?
    @State private var createdBuild: Build?
    /// The base Build the patch's checksum or title picked, selected once its Game's Builds load.
    @State private var matchedBuildID: UUID?
    @State private var usesPatchGameTitle = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("File", value: file.originalFilename)
                    LabeledContent("Suggested Filename", value: normalizedFilename)
                    Picker("Game", selection: $gameID) {
                        Text("Choose a Game").tag(nil as UUID?)
                        ForEach(games) { game in
                            Text(game.primaryTitle).tag(Optional(game.id))
                        }
                    }
                    .accessibilityIdentifier("sharedPatch.gamePicker")
                    Picker("Base Build", selection: $buildID) {
                        Text("Choose a Build").tag(nil as UUID?)
                        ForEach(builds) { build in
                            Text(build.displayName).tag(Optional(build.id))
                        }
                    }
                    .accessibilityIdentifier("sharedPatch.baseBuildPicker")
                    .disabled(gameID == nil)
                    LabeledContent("Build Name") {
                        TextField("New Build name", text: $displayName)
                            .accessibilityLabel("New Build name")
                            .multilineTextAlignment(.trailing)
                    }
                    if let title = offeredGameTitle {
                        Toggle("Use Game Title: \(title)", isOn: $usesPatchGameTitle)
                    }
                    DisclosureGroup("Naming Details") {
                        metadataField("Region", text: $region)
                        metadataField("Language", text: $language)
                        metadataField("Revision", text: $revision)
                        metadataField("Version", text: $version)
                        metadataField("Base Title", text: $baseTitle)
                        metadataField("Hack Title", text: $hackTitle)
                        metadataField("Author", text: $author)
                        metadataField("Translation", text: $translation)
                        metadataField("Status", text: $status)
                    }
                } footer: {
                    Text(games.isEmpty
                         ? "Import the original ROM into your library first, then open this patch again."
                         : "Choose the ROM this patch was made for. Applying it creates a new Build and keeps the original.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Apply Patch") { apply() }
                        .disabled(buildID == nil || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Open Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinished)
                }
            }
            .task {
                let naming = FilenameMetadataParser.parse(filename: file.originalFilename)
                self.naming = naming
                let metadata = BuildNaming.patchMetadata(for: naming)
                region = metadata.region ?? ""
                language = metadata.language ?? ""
                revision = metadata.revision ?? ""
                version = metadata.versionString ?? ""
                baseTitle = metadata.baseTitle ?? ""
                hackTitle = metadata.hackTitle ?? ""
                author = metadata.author ?? ""
                translation = metadata.translation ?? ""
                status = metadata.status ?? ""
                unknownGroups = naming.unknownGroups
                displayName = BuildNaming.patchBuildName(for: naming)
                suggestedBuildName = displayName
                do {
                    games = try container.repositories.games.fetchGames().sorted {
                        $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
                    }
                    matchBase(naming: naming)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: gameID) { _, selected in
                buildID = nil
                builds = []
                defer {
                    if displayName == suggestedBuildName, let naming {
                        suggestedBuildName = BuildNaming.distinctName(
                            BuildNaming.patchBuildName(
                                for: naming,
                                gameTitle: games.first(where: { $0.id == selected })?.primaryTitle
                            ),
                            existing: builds.map(\.displayName),
                            addedAt: .now
                        )
                        displayName = suggestedBuildName
                    }
                }
                guard let selected else { return }
                do {
                    builds = try container.repositories.builds.fetchBuilds(gameID: selected).sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    if let matchedBuildID, builds.contains(where: { $0.id == matchedBuildID }) {
                        buildID = matchedBuildID
                    }
                    matchedBuildID = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("This patch expects a different ROM", isPresented: Binding(
                get: { mismatchedBuild != nil },
                set: { if !$0 { mismatchedBuild = nil } }
            ), presenting: mismatchedBuild) { build in
                Button("Apply Anyway", role: .destructive) { apply(to: build, ignoringBaseMismatch: true) }
                Button("Cancel", role: .cancel) { mismatchedBuild = nil }
            } message: { build in
                Text("\(build.displayName) doesn't match the patch's expected base.\n\n\(baseMismatchDetails)\n\nApplying it anyway may produce a game that doesn't work.")
            }
            .alert("Build Created", isPresented: Binding(
                get: { createdBuild != nil },
                set: { if !$0 { createdBuild = nil } }
            ), presenting: createdBuild) { _ in
                Button("Done", action: onFinished)
            } message: { build in
                Text("“\(build.displayName)” is ready in your library.")
            }
        }
        .interactiveDismissDisabled()
    }

    /// Preselects the Game and base Build. A BPS names its base by size and CRC32; otherwise, or
    /// with no such Build, a Game matching the patch's title is chosen with its Base Build.
    private func matchBase(naming: FilenameMetadata) {
        var candidates: [(build: Build, byteLength: Int64)] = []
        for game in games {
            for build in container.builds(in: game.id) {
                if let asset = try? container.repositories.assets.fetchAsset(id: build.imageAssetID) {
                    candidates.append((build, asset.byteLength))
                }
            }
        }
        let matches = (try? Data(contentsOf: file.url)).map { patch in
            PatchBaseMatcher.builds(matchingPatch: patch, among: candidates) { build in
                try Data(contentsOf: container.launchImageResolver.resolve(buildID: build.id))
            }
        } ?? []
        if let match = matches.first(where: \.isBase) ?? matches.first,
           matches.allSatisfy({ $0.gameID == match.gameID }) {
            matchedBuildID = match.id
            gameID = match.gameID
        } else if matches.isEmpty,
                  let game = GameMatcher.matchingGameID(for: naming, headerTitle: "", in: games) {
            matchedBuildID = candidates.first { $0.build.gameID == game && $0.build.isBase }?.build.id
            gameID = game
        }
    }

    /// The patched Build becomes Preferred, so a patch naming a variant of the Game, such as
    /// "Mole Mania DX", offers that as the Game's title.
    private var offeredGameTitle: String? {
        guard let naming, let game = games.first(where: { $0.id == gameID }) else { return nil }
        return BuildNaming.patchGameTitle(for: naming, gameTitle: game.primaryTitle)
    }

    private func apply() {
        guard let build = builds.first(where: { $0.id == buildID }) else { return }
        apply(to: build)
    }

    private func apply(to build: Build, ignoringBaseMismatch: Bool = false) {
        mismatchedBuild = nil
        do {
            let title = usesPatchGameTitle ? offeredGameTitle : nil
            let created = try container.patchCreator.execute(.init(
                gameID: build.gameID,
                baseBuildID: build.id,
                patches: [.init(url: file.url, ignoreBaseMismatch: ignoringBaseMismatch)],
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                makePreferred: true,
                metadata: reviewedMetadata
            ))
            if let title {
                try? container.buildOperations.renameGame(gameID: created.gameID, title: title)
            }
            createdBuild = created
            errorMessage = nil
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch let error as PatchError where error.baseMismatchDescription != nil {
            baseMismatchDetails = error.baseMismatchDescription ?? ""
            mismatchedBuild = build
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var reviewedMetadata: BuildImportMetadata {
        let reviewedBase = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return BuildImportMetadata(
            region: region,
            language: language,
            revision: revision,
            versionString: version,
            baseTitle: reviewedBase.isEmpty ? games.first(where: { $0.id == gameID })?.primaryTitle : reviewedBase,
            hackTitle: hackTitle,
            author: author,
            translation: translation,
            status: status
        )
    }

    private var normalizedFilename: String {
        FilenameMetadataParser.canonicalFilename(
            fileExtension: file.url.pathExtension.lowercased(),
            title: hackTitle.isEmpty ? file.url.deletingPathExtension().lastPathComponent : hackTitle,
            metadata: reviewedMetadata,
            unknownGroups: unknownGroups
        )
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("Optional", text: text)
                .accessibilityLabel(label)
                .multilineTextAlignment(.trailing)
        }
    }
}
