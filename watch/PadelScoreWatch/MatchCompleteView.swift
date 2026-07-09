import SwiftUI

struct MatchCompleteView: View {
    @EnvironmentObject private var service: MatchService
    let match: MatchState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let winner = match.winner {
                    Text(winner == .left ? "Won" : "Lost")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(winner == .left ? .green : .orange)
                } else if match.status == .endedEarly {
                    Text("Ended Early")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Text(match.finalScoreSummary.isEmpty ? matchSummaryFallback : match.finalScoreSummary)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.center)

                Button {
                    service.acknowledgeCompletedMatch()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var title: String {
        switch match.status {
        case .completed: return "Match Complete"
        case .endedEarly: return "Match Ended Early"
        default: return "Match Over"
        }
    }

    private var matchSummaryFallback: String {
        "\(match.leftSetsWon)–\(match.rightSetsWon)"
    }
}
