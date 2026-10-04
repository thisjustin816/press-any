import EmulatorDomain
import QuickPlay
import SwiftUI

/// What to do with a Quick Play session: keep playing, add it to the library, or discard it.
/// Kept sessions expire after their retention window.
struct QuickPlaySessionView: View {
    let session: QuickPlaySession
    let container: AppContainer
    let onResume: (QuickPlaySession) -> Void
    let onFinished: () -> Void

    @State private var promotion: QuickPlayPromotionViewModel?
    @State private var confirmDiscard = false
    @State private var showsTechnicalInfo = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("File", value: session.originalFilename)
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Kept Until", value: session.expiresAt.formatted(date: .abbreviated, time: .shortened))
                if let source = sourceProfileName {
                    LabeledContent("Save", value: "Copy of \(source)")
                }
                Button {
                    showsTechnicalInfo = true
                } label: {
                    Label("Technical Info", systemImage: "info.circle")
                }
            } footer: {
                Text("Nothing from this session is in your library until you add it.")
            }

            Section {
                Button {
                    onResume(session)
                } label: {
                    Label("Keep Playing", systemImage: "play.fill")
                }
                Button {
                    do {
                        promotion = try QuickPlayPromotionViewModel(session: session, container: container)
                    } catch {
                        errorMessage = "Couldn’t review this session: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Add to Library…", systemImage: "square.and.arrow.down.on.square")
                }
                Button(role: .destructive) {
                    confirmDiscard = true
                } label: {
                    Label("Discard", systemImage: "trash")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Quick Play")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $promotion) { model in
            QuickPlayPromotionView(model: model, onPromoted: onFinished)
        }
        .sheet(isPresented: $showsTechnicalInfo) {
            QuickPlayTechnicalInfoView(session: session)
        }
        .task {
            if case .quickPlayInfo = ScreenshotScene.current { showsTechnicalInfo = true }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                do {
                    try container.quickPlayWorkspace.discard(sessionID: session.id)
                    onFinished()
                } catch {
                    errorMessage = "Couldn’t discard the session: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("Its save and progress are deleted. Library saves it copied from are not affected.")
        }
    }

    private var sourceProfileName: String? {
        guard let id = session.sourceSaveProfileID else { return nil }
        return (try? container.repositories.saveProfiles.fetchSaveProfile(id: id))?.displayName ?? "a deleted profile"
    }
}

extension QuickPlayPromotionViewModel: Hashable {
    nonisolated static func == (lhs: QuickPlayPromotionViewModel, rhs: QuickPlayPromotionViewModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

struct QuickPlayPromotionView: View {
    @ObservedObject var model: QuickPlayPromotionViewModel
    let onPromoted: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ImportDestinationSection(model: model.review)

            ToolchainSection(reports: model.review.analysis.toolchainReports)

            Section {
                if model.hasSave {
                    Picker("Save", selection: $model.saveChoice) {
                        Text("New Save Profile").tag(QuickPlayPromotionViewModel.SaveChoice.newProfile)
                        if model.canReplaceSource, let source = model.sourceProfile {
                            Text("Replace \(source.displayName)").tag(QuickPlayPromotionViewModel.SaveChoice.replaceSource)
                        }
                        Text("Don’t Keep It").tag(QuickPlayPromotionViewModel.SaveChoice.discard)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if model.effectiveSaveChoice == .newProfile {
                        TextField("Profile name", text: $model.newProfileName)
                    }
                } else {
                    Text("This session has no battery save.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Save")
            } footer: {
                if model.effectiveSaveChoice == .replaceSource, let source = model.sourceProfile {
                    Text("\(source.displayName) is copied to “\(source.displayName) before Quick Play” first.")
                }
            }

            if let message = model.errorMessage ?? model.review.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add to Library")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    model.cancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if (try? model.promote()) != nil { onPromoted() }
                }
                .disabled(!model.review.canCommit || model.needsFreshReview)
            }
        }
    }
}

/// Quick Play sessions kept for later, newest first.
struct QuickPlaySessionsView: View {
    let container: AppContainer
    let onResume: (QuickPlaySession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [QuickPlaySession] = []
    @State private var selected: QuickPlaySession?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Quick Play Sessions",
                        systemImage: "play.circle",
                        description: Text("Sessions you keep stay here until they expire.")
                    )
                } else {
                    List(sessions) { session in
                        Button {
                            selected = session
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.originalFilename)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Quick Play Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selected) { session in
                QuickPlaySessionView(
                    session: session,
                    container: container,
                    onResume: { resumed in
                        onResume(resumed)
                        dismiss()
                    },
                    onFinished: {
                        selected = nil
                        reload()
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        sessions = (try? container.quickPlayWorkspace.sessions()) ?? []
    }
}

/// Picks the library save a Quick Play session starts from. The session gets a copy.
struct QuickPlaySaveChooser: View {
    let container: AppContainer
    let onChoose: (SaveProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    private struct GameSaves: Identifiable {
        let game: Game
        let profiles: [SaveProfile]
        var id: UUID { game.id }
    }

    @State private var games: [GameSaves] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(games) { entry in
                    Section(entry.game.primaryTitle) {
                        ForEach(entry.profiles) { profile in
                            Button(profile.displayName) {
                                onChoose(profile)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .overlay {
                if games.isEmpty {
                    ContentUnavailableView(
                        "No Saves",
                        systemImage: "externaldrive",
                        description: Text("Library games have no Save Profiles yet.")
                    )
                }
            }
            .navigationTitle("Quick Play with a Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let repositories = container.repositories
        let allGames = (try? repositories.games.fetchGames()) ?? []
        games = allGames
            .sorted { $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending }
            .compactMap { game in
                let profiles = ((try? repositories.saveProfiles.fetchSaveProfiles(gameID: game.id)) ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                return profiles.isEmpty ? nil : GameSaves(game: game, profiles: profiles)
            }
    }
}
