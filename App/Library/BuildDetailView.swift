import EmulatorDomain
import SwiftUI

struct BuildDetailView: View {
    @StateObject private var model: BuildDetailViewModel
    @State private var showsTechnicalInfo = false
    @Environment(\.dismiss) private var dismiss
    let container: AppContainer

    init(build: Build, container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: BuildDetailViewModel(
            buildID: build.id,
            builds: container.repositories.builds,
            operations: container.buildOperations
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                if let build = model.build {
                    Section {
                        LabeledContent("Playtime", value: BuildPlaytime.formatted(build.totalPlaytimeSeconds))
                            .accessibilityIdentifier("build.playtime")
                        Button("Technical Info…") { showsTechnicalInfo = true }
                    }
                    Section("Notes") {
                        Text(verbatim: build.notes.isEmpty ? "No notes" : build.notes)
                            .foregroundStyle(build.notes.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("build.notes")
                        Button("Edit Notes…", systemImage: "pencil") { model.editNotes() }
                    }
                }
            }
            .navigationTitle(model.build?.displayName ?? "Build Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { model.reload() }
            .sheet(isPresented: $showsTechnicalInfo) {
                if let build = model.build { BuildTechnicalInfoView(build: build, container: container) }
            }
            .sheet(isPresented: $model.isEditingNotes) { notesEditor }
            .alert("Build Error", isPresented: Binding(
                get: { model.errorMessage != nil && !model.isEditingNotes },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
    }

    private var notesEditor: some View {
        NavigationStack {
            Form {
                TextEditor(text: $model.notesDraft)
                    .frame(minHeight: 200)
                    .accessibilityLabel("Build Notes")
                    .accessibilityIdentifier("build.notesEditor")
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.isEditingNotes = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveNotes() }
                }
            }
        }
    }
}
