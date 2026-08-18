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
            let remaining = match.warmUpRemaining(at: context.date)
            VStack(spacing: 12) {
                Text("Warm up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                Text(DurationFormatter.countdown(remaining))
                    .font(.title.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Warm up remaining \(DurationFormatter.countdown(remaining))")

                Button("Skip") {
                    finishWarmUp()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Skip warm up")
                .accessibilityHint("Go to who is serving")
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
        if match.warmUpRemaining() <= 0 {
            finishWarmUp()
        }
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        let remaining = match.warmUpRemaining()
        guard remaining > 0 else { return }
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
}
