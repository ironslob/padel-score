import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PadelScoreLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MatchLiveActivityWidget()
    }
}

struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            MatchLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.gameLeft)
                        .font(.title2.monospacedDigit().weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.gameRight)
                        .font(.title2.monospacedDigit().weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Set \(context.state.setLeft)–\(context.state.setRight)")
                        .font(.caption.monospacedDigit())
                }
            } compactLeading: {
                Text(context.state.gameLeft)
                    .monospacedDigit()
            } compactTrailing: {
                Text(context.state.gameRight)
                    .monospacedDigit()
            } minimal: {
                Text(context.state.gameLeft)
                    .monospacedDigit()
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

struct MatchLiveActivityView: View {
    let context: ActivityViewContext<MatchActivityAttributes>

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        switch activityFamily {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.state.gameLeft)–\(context.state.gameRight)")
                    .font(.headline.monospacedDigit())
                Text("Set \(context.state.setLeft)–\(context.state.setRight)")
                    .font(.caption.monospacedDigit())
                Text(
                    DurationFormatter.elapsed(
                        Date().timeIntervalSince(context.state.startedAt)
                    )
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Padel Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(context.state.gameLeft)–\(context.state.gameRight)")
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("Set \(context.state.setLeft)–\(context.state.setRight)")
                    .font(.subheadline.monospacedDigit())
                Text(
                    DurationFormatter.elapsed(
                        Date().timeIntervalSince(context.state.startedAt)
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
