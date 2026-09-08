import SwiftUI

struct MatchDetailView: View {
    let match: MatchState
    /// Phone-authored free text for this match; editing is hidden without `onNoteChange`.
    var note: String = ""
    var onNoteChange: ((String) -> Void)?
    /// Supplied for history entries only; the active match is owned by the Watch.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingDelete = false
    @State private var noteDraft = ""
    @FocusState private var isNoteFocused: Bool
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

            if onNoteChange != nil {
                Section("Notes") {
                    TextField("Add a note", text: $noteDraft, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($isNoteFocused)
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
                    ForEach(Array(historyRows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text(row.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Event \(index + 1): \(row.label)")
                    }
                } label: {
                    HStack {
                        Text("Scoring History")
                        Spacer()
                        Text("\(historyRows.count)")
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
            // A multi-line field takes Return as a newline, so it needs its own dismissal.
            ToolbarItem(placement: .keyboard) {
                if isNoteFocused {
                    Button("Done") { isNoteFocused = false }
                }
            }
        }
        .onAppear { noteDraft = note }
        .onChange(of: note) { _, newNote in
            if !isNoteFocused { noteDraft = newNote }
        }
        .onChange(of: isNoteFocused) { _, focused in
            if !focused { saveNote() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNote() }
        }
        .onDisappear { saveNote() }
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

    private func saveNote() {
        onNoteChange?(noteDraft)
    }

    private var scoreText: String {
        let summary = match.finalScoreSummary
        return summary.isEmpty ? "\(match.leftSetsWon)–\(match.rightSetsWon)" : summary
    }

    private var incompleteSetLabel: String {
        match.status == .inProgress ? "Current" : "Set \(match.completedSets.count + 1)"
    }

    private struct HistoryRow: Identifiable {
        let id: String
        let timestamp: Date
        let label: String
    }

    private var historyRows: [HistoryRow] {
        var rows = match.events.map { event in
            HistoryRow(id: event.id.uuidString, timestamp: event.timestamp, label: eventLabel(event))
        }
        for (index, change) in match.deuceFormatChanges.enumerated() where index > 0 {
            rows.append(
                HistoryRow(
                    id: "deuce-\(index)-\(change.at.timeIntervalSince1970)",
                    timestamp: change.at,
                    label: "Scoring at deuce: \(change.format.label)"
                )
            )
        }
        return rows.sorted { $0.timestamp < $1.timestamp }
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
