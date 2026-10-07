import EmulatorDomain
import QuickPlay
import SwiftUI

/// What to do with a Quick Play session: keep playing, add it to the library, or discard it.
/// Kept sessions expire after their retention window.
struct QuickPlaySessionView: View {
    let session: QuickPlaySession
    let container: AppContainer
    /// Opens straight to Add to Library, as the game menu's Add to Library asks.
    var addsToLibrary = false
    let onResume: (QuickPlaySession) -> Void
    let onFinished: () -> Void

    @State private var promotion: QuickPlayPromotionViewModel?
    @State private var confirmDiscard = false
    @State private var showsTechnicalInfo = false
    @State private var errorMessage: String?
    /// The task runs again whenever the view reappears, such as after Add to Library is canceled,
    /// so it opens Technical Info or Add to Library only the first time.
    @State private var openedOnAppear = false

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
                    startPromotion()
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
            guard !openedOnAppear else { return }
            openedOnAppear = true
            if case .quickPlayInfo = ScreenshotScene.current { showsTechnicalInfo = true }
            if addsToLibrary { startPromotion() }
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
            Text(Self.discardMessage)
        }
    }

    static let discardMessage = "Its save and progress are deleted. Library saves it copied from are not affected."

    private func startPromotion() {
        do {
            promotion = try QuickPlayPromotionViewModel(session: session, container: container)
        } catch {
            errorMessage = "Couldn’t review this session: \(error.localizedDescription)"
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
                if model.hasProgress {
                    Picker("Keep Progress", selection: $model.saveChoice) {
                        Text("Create New Save Profile").tag(QuickPlayPromotionViewModel.SaveChoice.newProfile)
                        if model.canReplaceSource, let source = model.sourceProfile {
                            Text("Replace \(source.displayName)").tag(QuickPlayPromotionViewModel.SaveChoice.replaceSource)
                        }
                        Text("Don’t Keep Quick Play Progress").tag(QuickPlayPromotionViewModel.SaveChoice.discard)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if model.effectiveSaveChoice == .newProfile {
                        LabeledContent("Profile Name") {
                            TextField("Profile Name", text: $model.newProfileName)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } else {
                    Text("This session has no save and nowhere to resume.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Save Progress")
            } footer: {
                if model.effectiveSaveChoice == .replaceSource, let source = model.sourceProfile {
                    Text("\(source.displayName) is copied to “\(source.displayName) before Quick Play” first.")
                } else if model.hasResumePoint, !model.hasBattery, model.effectiveSaveChoice == .newProfile {
                    Text("This game doesn’t save on its own. The new profile keeps where you left off.")
                } else if model.effectiveSaveChoice == .newProfile {
                    Text("Quick Play progress will be saved in a new profile with this name.")
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
        .alert(
            "Added to Library",
            isPresented: Binding(get: { model.shortfallNotice != nil }, set: { if !$0 { model.shortfallNotice = nil } })
        ) {
            Button("OK") { onPromoted() }
        } message: {
            Text(model.shortfallNotice ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    model.cancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard (try? model.promote()) != nil else { return }
                    if model.shortfallNotice == nil { onPromoted() }
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
    @State private var discardTarget: QuickPlaySession?
    @State private var errorMessage: String?
    @State private var selection = ItemSelection<UUID>()
    @State private var batchDiscard: [QuickPlaySession]?

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
                    List(selection: selection.isSelecting ? $selection.ids : nil) {
                        ForEach(sessions) { session in
                            Group {
                                if selection.isSelecting {
                                    sessionLabel(session)
                                } else {
                                    Button { selected = session } label: { sessionLabel(session) }
                                        .foregroundStyle(.primary)
                                        .swipeActions(edge: .trailing) {
                                            SwipeDeleteButton(title: "Discard") { discardTarget = session }
                                        }
                                }
                            }
                            .tag(session.id)
                        }
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
            .selectionControls(selection: $selection, available: Set(sessions.map(\.id)), action: "Discard") {
                batchDiscard = sessions.filter { selection.ids.contains($0.id) }
            }
            .confirmationDialog("Discard \(batchDiscard?.count ?? 0) \((batchDiscard?.count ?? 0) == 1 ? "Session" : "Sessions")?", isPresented: Binding(
                get: { batchDiscard != nil },
                set: { if !$0 { batchDiscard = nil } }
            ), titleVisibility: .visible, presenting: batchDiscard) { sessions in
                Button("Discard (\(sessions.count))", role: .destructive) { discardSelected(sessions) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Their saves and progress are deleted. Library saves they copied from are not affected. This can't be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !selection.isSelecting { Button("Done") { dismiss() } }
                }
            }
            .onAppear(perform: reload)
            .confirmationDialog("Discard this session?", isPresented: Binding(
                get: { discardTarget != nil },
                set: { if !$0 { discardTarget = nil } }
            ), titleVisibility: .visible, presenting: discardTarget) { session in
                Button("Discard", role: .destructive) { discard(session) }
            } message: { _ in
                Text(QuickPlaySessionView.discardMessage)
            }
            .alert("Quick Play", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func sessionLabel(_ session: QuickPlaySession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.originalFilename)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func discardSelected(_ sessions: [QuickPlaySession]) {
        var failures: [String] = []
        for session in sessions {
            do {
                try container.quickPlayWorkspace.discard(sessionID: session.id)
                selection.ids.remove(session.id)
            } catch {
                failures.append("\(session.originalFilename): \(error.localizedDescription)")
            }
        }
        reload()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n\n") }
    }

    private func reload() {
        sessions = (try? container.quickPlayWorkspace.sessions()) ?? []
        selection.reconcile(with: Set(sessions.map(\.id)))
    }

    private func discard(_ session: QuickPlaySession) {
        do {
            try container.quickPlayWorkspace.discard(sessionID: session.id)
        } catch {
            errorMessage = "Couldn’t discard the session: \(error.localizedDescription)"
        }
        reload()
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
