import SwiftUI

struct MatchDetailView: View {
    let match: MatchState
    /// Supplied for history entries only; the active match is owned by the Watch.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isHistoryExpanded = false

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Status", value: match.status.displayName)
                LabeledContent("Started", value: match.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let finished = match.finishedAt {
                    LabeledContent("Finished", value: finished.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Duration", value: DurationFormatter.detailed(match.duration))
                LabeledContent("Score", value: scoreText)
                if let winner = match.winner {
                    LabeledContent("Winner", value: winner == .left ? "Us (left)" : "Them (right)")
                }
            }

            Section("Sets") {
                if match.completedSets.isEmpty && match.status == .inProgress {
                    Text("No completed sets yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(match.completedSets.enumerated()), id: \.offset) { index, set in
                    Text("Set \(index + 1): \(set.leftGames)–\(set.rightGames)")
                        .monospacedDigit()
                }
                if match.displaysIncompleteSet {
                    Text("\(incompleteSetLabel): \(match.currentSet.leftGames)–\(match.currentSet.rightGames) (Game \(match.gameDisplayPair.left)–\(match.gameDisplayPair.right))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isHistoryExpanded) {
                    ForEach(Array(match.events.enumerated()), id: \.element.id) { index, event in
                        HStack {
                            Text(eventLabel(event))
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Event \(index + 1): \(eventLabel(event))")
                    }
                } label: {
                    HStack {
                        Text("Scoring History")
                        Spacer()
                        Text("\(match.events.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Match")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this match?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. The match is removed from your Apple Watch too.")
        }
    }

    private var scoreText: String {
        let summary = match.finalScoreSummary
        return summary.isEmpty ? "\(match.leftSetsWon)–\(match.rightSetsWon)" : summary
    }

    private var incompleteSetLabel: String {
        match.status == .inProgress ? "Current" : "Set \(match.completedSets.count + 1)"
    }

    private func eventLabel(_ event: MatchEvent) -> String {
        switch event.kind {
        case .matchStarted:
            return "Match started"
        case .serverSelected:
            return "Server: \(event.side?.displayName ?? "?")"
        case .pointWon:
            return "Point: \(event.side?.displayName ?? "?")"
        case .matchFinished:
            return "Match finished"
        case .matchEndedEarly:
            return "Ended early"
        case .matchDiscarded:
            return "Discarded"
        }
    }
}
