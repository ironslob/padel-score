import SwiftUI

struct WarmUpView: View {
    @EnvironmentObject private var service: MatchService
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let match: MatchState

    @State private var completionTask: Task<Void, Never>?

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: isLuminanceReduced
            )
        ) { context in
            let elapsed = match.warmUpElapsed(at: context.date)
            VStack(spacing: 12) {
                Text("Warm up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                Text(DurationFormatter.countdown(elapsed))
                    .font(.title.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Warm up \(DurationFormatter.countdown(elapsed))")

                Button {
                    finishWarmUp()
                } label: {
                    Text("Play")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .watchButtonBorderShape()
                .tint(.green)
                .accessibilityLabel("Play")
                .accessibilityHint("Go to who is serving")

                Button {
                    cancelWarmUp()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .watchButtonBorderShape()
                .accessibilityLabel("Back")
                .accessibilityHint("Return to the start screen without starting the match")
            }
            .padding()
        }
        .onAppear {
            finishIfExpired()
            scheduleCompletion()
        }
        .onDisappear {
            completionTask?.cancel()
            completionTask = nil
        }
    }

    private func finishIfExpired() {
        if match.isWarmUpExpired() {
            finishWarmUp()
        }
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        guard let remaining = match.warmUpRemaining(), remaining > 0 else { return }
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if Task.isCancelled { return }
            finishWarmUp()
        }
    }

    private func finishWarmUp() {
        completionTask?.cancel()
        completionTask = nil
        service.completeWarmUp()
    }

    private func cancelWarmUp() {
        completionTask?.cancel()
        completionTask = nil
        service.discardMatch()
    }
}
