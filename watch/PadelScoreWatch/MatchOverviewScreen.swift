import SwiftUI

struct MatchOverviewScreen: View {
    let match: MatchState
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                labeled("Current Set", "\(match.currentSet.leftGames) – \(match.currentSet.rightGames)")
                labeled("Current Match", "\(match.leftSetsWon) – \(match.rightSetsWon)")
                labeled("Elapsed", DurationFormatter.elapsed(now.timeIntervalSince(match.startedAt)))

                if match.currentGame.isGoldenPointActive {
                    Text("Golden Point")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                    Text("Next point wins")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !match.completedSets.isEmpty {
                    Text("Sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(match.completedSets.enumerated()), id: \.offset) { index, set in
                        Text("Set \(index + 1): \(set.leftGames)–\(set.rightGames)")
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onReceive(timer) { now = $0 }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
