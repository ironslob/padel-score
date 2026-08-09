import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var appModel: PhoneAppModel
    @EnvironmentObject private var service: MatchService
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDeletion: [MatchState] = []

    var body: some View {
        NavigationStack {
            Group {
                if service.isRestored {
                    matchList
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Padel Score")
            .toolbar {
                if !historyMatches.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .overlay {
                if service.isRestored, service.activeMatch == nil, service.archivedMatches.isEmpty {
                    ContentUnavailableView(
                        "No Matches Yet",
                        systemImage: "applewatch",
                        description: Text("Start a match on your Apple Watch. Completed matches will appear here.")
                    )
                }
            }
            .refreshable {
                service.restore()
            }
            .confirmationDialog(
                deletionPrompt,
                isPresented: Binding(
                    get: { !pendingDeletion.isEmpty },
                    set: { if !$0 { pendingDeletion = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    for match in pendingDeletion {
                        service.deleteArchivedMatch(id: match.id)
                    }
                    pendingDeletion = []
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = []
                }
            } message: {
                Text("This can't be undone. The match is removed from your Apple Watch too.")
            }
        }
        .task {
            await appModel.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                service.expireInactiveMatchIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var matchList: some View {
        List {
            if let active = service.activeMatch, active.status == .inProgress || active.status.isTerminal {
                Section("Active Match") {
                    NavigationLink {
                        MatchDetailView(
                            match: active,
                            note: service.note(for: active.id),
                            onNoteChange: { service.setNote($0, for: active.id) }
                        )
                    } label: {
                        ActiveMatchRow(match: active)
                    }
                }
            }

            Section("History") {
                if historyMatches.isEmpty {
                    Text("No completed matches yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyMatches) { match in
                        NavigationLink {
                            MatchDetailView(
                                match: match,
                                note: service.note(for: match.id),
                                onNoteChange: { service.setNote($0, for: match.id) },
                                onDelete: { service.deleteArchivedMatch(id: match.id) }
                            )
                        } label: {
                            MatchHistoryRow(match: match, note: service.note(for: match.id))
                        }
                    }
                    .onDelete { offsets in
                        pendingDeletion = offsets.map { historyMatches[$0] }
                    }
                }
            }
        }
    }

    /// The active match is archived as soon as it reaches a terminal state but stays
    /// active until acknowledged on the Watch, so it would otherwise appear twice.
    private var historyMatches: [MatchState] {
        service.archivedMatches.filter { $0.id != service.activeMatch?.id }
    }

    private var deletionPrompt: String {
        pendingDeletion.count > 1 ? "Delete \(pendingDeletion.count) matches?" : "Delete this match?"
    }
}

struct ActiveMatchRow: View {
    let match: MatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.status == .inProgress ? "In Progress" : match.status.displayName)
                    .font(.headline)
                Spacer()
                Text("\(match.leftSetsWon)–\(match.rightSetsWon)")
                    .font(.title3.monospacedDigit().weight(.bold))
            }
            Text("Set \(match.currentSet.leftGames)–\(match.currentSet.rightGames) · Game \(match.gameDisplayPair.left)–\(match.gameDisplayPair.right)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if match.currentGame.isGoldenPointActive {
                Text(match.settings.deuceFormat.decidingPointLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MatchHistoryRow: View {
    let match: MatchState
    var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                Text(match.status.displayName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Text(match.finalScoreSummary.isEmpty ? "\(match.leftSetsWon)–\(match.rightSetsWon)" : match.finalScoreSummary)
                .font(.subheadline.monospacedDigit())
            Text(DurationFormatter.detailed(match.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch match.status {
        case .completed: return .green
        case .endedEarly: return .orange
        case .inProgress: return .blue
        case .discarded: return .secondary
        }
    }
}
