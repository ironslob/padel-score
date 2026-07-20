import SwiftUI

struct MatchDetailView: View {
    let match: MatchState

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
                    Text("\(incompleteSetLabel): \(match.currentSet.leftGames)–\(match.currentSet.rightGames) (Game \(match.currentGame.displayPair.left)–\(match.currentGame.displayPair.right))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section("Scoring History") {
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
            }
        }
        .navigationTitle("Match")
        .navigationBarTitleDisplayMode(.inline)
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
