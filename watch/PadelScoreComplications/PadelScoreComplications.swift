import WidgetKit
import SwiftUI

@main
struct PadelScoreComplicationsBundle: WidgetBundle {
    var body: some Widget {
        ScoreComplicationWidget()
    }
}

struct ScoreComplicationWidget: Widget {
    let kind = "ScoreComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScoreComplicationProvider()) { entry in
            ScoreComplicationView(entry: entry)
        }
        .configurationDisplayName("Padel Score")
        .description("Shows the current match score.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct ScoreComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: MatchScoreSnapshot
}

struct ScoreComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreComplicationEntry {
        ScoreComplicationEntry(
            date: Date(),
            snapshot: MatchScoreSnapshot(
                gameLeft: "40",
                gameRight: "30",
                setLeft: "4",
                setRight: "3",
                isInProgress: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoreComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreComplicationEntry>) -> Void) {
        let entry = currentEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> ScoreComplicationEntry {
        ScoreComplicationEntry(
            date: Date(),
            snapshot: MatchScoreSnapshotStore.load()
                ?? MatchScoreSnapshot(
                    gameLeft: "-",
                    gameRight: "-",
                    setLeft: "-",
                    setRight: "-",
                    isInProgress: false
                )
        )
    }
}

struct ScoreComplicationView: View {
    let entry: ScoreComplicationEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Padel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if entry.snapshot.isInProgress {
                    Text(entry.snapshot.gameLabel)
                        .font(.headline.monospacedDigit())
                    Text("Set \(entry.snapshot.setLabel)")
                        .font(.caption.monospacedDigit())
                } else {
                    Text("No match")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(entry.snapshot.isInProgress ? entry.snapshot.compactLabel : "Padel: No match")
        case .accessoryCorner:
            Text(entry.snapshot.isInProgress ? entry.snapshot.gameLabel : "--")
                .font(.headline.monospacedDigit())
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if entry.snapshot.isInProgress {
                        Text(entry.snapshot.gameLabel)
                            .font(.caption2.weight(.bold).monospacedDigit())
                        Text(entry.snapshot.setLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }
}
