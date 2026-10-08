import EmulatorApplication
import EmulatorDomain
import SwiftUI

struct MetadataDetailsView: View {
    let buildID: UUID
    let container: AppContainer

    @State private var build: Build?
    @State private var game: Game?
    @State private var titleProvenance: MetadataProvenance?
    @State private var buildProvenance: [MetadataProvenance] = []
    @State private var editingField = MetadataField.title
    @State private var draft = ""
    @State private var isEditing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if build != nil, game != nil {
                ForEach(MetadataField.allCases, id: \.self) { field in
                    Section(field.label) {
                        Button {
                            editingField = field
                            draft = value(for: field) ?? ""
                            isEditing = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: value(for: field) ?? "None")
                                    .foregroundStyle(.primary)
                                if let row = provenance(for: field) {
                                    Text(row.source.label)
                                    if let confidence = row.confidence {
                                        Text("Confidence: \(confidence.rawValue.capitalized)")
                                    }
                                    Text("Recorded: \(row.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                                    if row.providedValue != value(for: field) {
                                        Text(verbatim: "Offered: \(row.providedValue ?? "None")")
                                    }
                                } else {
                                    Text("Not recorded")
                                }
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metadata.\(field.rawValue)")
                        if let row = provenance(for: field), row.source == .player, let offered = row.providedValue,
                           offered != value(for: field) {
                            Button("Use Offered Value") { save(field: field, value: offered) }
                                .accessibilityIdentifier("metadata.useOffered.\(field.rawValue)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Metadata Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .sheet(isPresented: $isEditing) { editor }
        .alert("Metadata Error", isPresented: Binding(
            get: { errorMessage != nil && !isEditing },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                TextField(editingField.label, text: $draft, axis: .vertical)
                    .accessibilityIdentifier("metadata.editor")
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Edit \(editingField.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        errorMessage = nil
                        isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(field: editingField, value: draft) }
                        .disabled((editingField == .title || editingField == .displayName)
                            && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func value(for field: MetadataField) -> String? {
        if field == .title { return game?.primaryTitle }
        return build.flatMap { field.value(in: $0) }
    }

    private func provenance(for field: MetadataField) -> MetadataProvenance? {
        field == .title ? titleProvenance : buildProvenance.first { $0.field == field }
    }

    private func reload() {
        do {
            guard let fetched = try container.repositories.builds.fetchBuild(id: buildID) else {
                throw BuildOperationError.buildNotFound(buildID)
            }
            guard let owner = try container.repositories.games.fetchGame(id: fetched.gameID) else {
                throw BuildOperationError.gameNotFound(fetched.gameID)
            }
            build = fetched
            game = owner
            titleProvenance = try container.repositories.games.fetchMetadataProvenance(ownerID: owner.id)
                .first { $0.field == .title }
            buildProvenance = try container.repositories.builds.fetchMetadataProvenance(ownerID: buildID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(field: MetadataField, value: String) {
        do {
            switch field {
            case .title:
                guard let game else { return }
                try container.buildOperations.renameGame(gameID: game.id, title: value)
            case .displayName:
                try container.buildOperations.renameBuild(buildID: buildID, displayName: value)
            default:
                try container.buildOperations.setMetadata(buildID: buildID, field: field, value: value)
            }
            isEditing = false
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension MetadataField {
    var label: String {
        switch self {
        case .title: "Game Title"
        case .displayName: "Display Name"
        case .region: "Region"
        case .language: "Language"
        case .revision: "Revision"
        case .versionString: "Version"
        case .baseTitle: "Base Title"
        case .hackTitle: "Hack Title"
        case .author: "Author"
        case .translation: "Translation"
        case .status: "Status"
        }
    }
}

private extension MetadataSource {
    var label: String {
        switch self {
        case .noIntro: "No-Intro"
        case .romHeader: "ROM Header"
        case .filename: "Filename"
        case .patch: "Patch"
        case .player: "You"
        }
    }
}
