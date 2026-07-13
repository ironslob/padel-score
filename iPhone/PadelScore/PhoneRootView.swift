import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var appModel: PhoneAppModel
    @EnvironmentObject private var service: MatchService
    @Environment(\.scenePhase) private var scenePhase

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
                        MatchDetailView(match: active)
                    } label: {
                        ActiveMatchRow(match: active)
                    }
                }
            }

            Section("History") {
                if service.archivedMatches.isEmpty {
                    Text("No completed matches yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.archivedMatches) { match in
                        NavigationLink {
                            MatchDetailView(match: match)
                        } label: {
                            MatchHistoryRow(match: match)
                        }
                    }
                }
            }
        }
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
            Text("Set \(match.currentSet.leftGames)–\(match.currentSet.rightGames) · Game \(match.currentGame.displayPair.left)–\(match.currentGame.displayPair.right)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if match.currentGame.isGoldenPointActive {
                Text("Golden Point")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MatchHistoryRow: View {
    let match: MatchState

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
