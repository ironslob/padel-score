import WidgetKit
import SwiftUI

@main
struct PadelScoreComplicationsBundle: WidgetBundle {
    var body: some Widget {
        ScoreComplicationWidget()
        MatchGlanceWidget()
    }
}

// MARK: - Watch face complications

struct ScoreComplicationWidget: Widget {
    let kind = "ScoreComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScoreComplicationProvider()) { entry in
            ScoreComplicationView(entry: entry)
        }
        .configurationDisplayName("Padel Score")
        .description("Shows the current match score on your watch face.")
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
    let relevance: TimelineEntryRelevance?
}

struct ScoreComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreComplicationEntry {
        sampleEntry(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoreComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreComplicationEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let timeline = MatchGlanceTimelineBuilder.timeline(for: snapshot) { date, snap in
            ScoreComplicationEntry(
                date: date,
                snapshot: snap,
                relevance: snap.isInProgress ? TimelineEntryRelevance(score: 80) : nil
            )
        }
        completion(timeline)
    }

    private func currentEntry() -> ScoreComplicationEntry {
        sampleEntry(at: Date(), snapshot: loadSnapshot())
    }

    private func sampleEntry(at date: Date, snapshot: MatchScoreSnapshot? = nil) -> ScoreComplicationEntry {
        ScoreComplicationEntry(
            date: date,
            snapshot: snapshot ?? MatchScoreSnapshot(
                gameLeft: "40",
                gameRight: "30",
                setLeft: "4",
                setRight: "3",
                isInProgress: true,
                startedAt: date.addingTimeInterval(-720)
            ),
            relevance: TimelineEntryRelevance(score: 80)
        )
    }

    private func loadSnapshot() -> MatchScoreSnapshot {
        MatchScoreSnapshotStore.load()
            ?? MatchScoreSnapshot(
                gameLeft: "-",
                gameRight: "-",
                setLeft: "-",
                setRight: "-",
                isInProgress: false
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
                    if let elapsed = entry.snapshot.elapsedLabel(at: entry.date) {
                        Text(elapsed)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No match")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(inlineLabel)
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
                        if let indicator = statusIndicator {
                            Text(indicator)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("--")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }

    private var inlineLabel: String {
        guard entry.snapshot.isInProgress else { return "Padel: No match" }
        var parts = [entry.snapshot.gameLabel, entry.snapshot.setLabel]
        if let elapsed = entry.snapshot.elapsedLabel(at: entry.date) {
            parts.append(elapsed)
        }
        return parts.joined(separator: " · ")
    }

    private var statusIndicator: String? {
        if entry.snapshot.isGoldenPointActive { return "GP" }
        if entry.snapshot.isTieBreak { return "TB" }
        return nil
    }
}

// MARK: - Smart Stack glance widget

struct MatchGlanceWidget: Widget {
    let kind = "MatchGlance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatchGlanceProvider()) { entry in
            MatchGlanceView(entry: entry)
                .widgetURL(URL(string: "padelscore://score"))
        }
        .configurationDisplayName("Match Glance")
        .description("Game score, set games, and elapsed time during a match.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct MatchGlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: MatchScoreSnapshot
    let relevance: TimelineEntryRelevance?
}

struct MatchGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchGlanceEntry {
        MatchGlanceEntry(
            date: Date(),
            snapshot: MatchScoreSnapshot(
                gameLeft: "40",
                gameRight: "30",
                setLeft: "4",
                setRight: "3",
                isInProgress: true,
                startedAt: Date().addingTimeInterval(-600)
            ),
            relevance: TimelineEntryRelevance(score: 100)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MatchGlanceEntry) -> Void) {
        let snapshot = loadSnapshot()
        completion(
            MatchGlanceEntry(
                date: Date(),
                snapshot: snapshot,
                relevance: snapshot.isInProgress ? TimelineEntryRelevance(score: 100) : nil
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchGlanceEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let timeline = MatchGlanceTimelineBuilder.timeline(for: snapshot) { date, snap in
            MatchGlanceEntry(
                date: date,
                snapshot: snap,
                relevance: snap.isInProgress ? TimelineEntryRelevance(score: 100) : nil
            )
        }
        completion(timeline)
    }

    private func loadSnapshot() -> MatchScoreSnapshot {
        MatchScoreSnapshotStore.load()
            ?? MatchScoreSnapshot(
                gameLeft: "-",
                gameRight: "-",
                setLeft: "-",
                setRight: "-",
                isInProgress: false
            )
    }
}

struct MatchGlanceView: View {
    let entry: MatchGlanceEntry

    var body: some View {
        Group {
            if entry.snapshot.isInProgress {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.gameLabel)
                        .font(.headline.monospacedDigit())
                    Text("Set \(entry.snapshot.setLabel)")
                        .font(.caption.monospacedDigit())
                    if let elapsed = entry.snapshot.elapsedLabel(at: entry.date) {
                        Text(elapsed)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Padel Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("No active match")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

// MARK: - Timeline helpers

enum MatchGlanceTimelineBuilder {
    private static let refreshInterval: TimeInterval = 30
    private static let activeHorizon: TimeInterval = 3_600

    static func timeline<Entry: TimelineEntry>(
        for snapshot: MatchScoreSnapshot,
        makeEntry: (Date, MatchScoreSnapshot) -> Entry
    ) -> Timeline<Entry> {
        let now = Date()

        guard snapshot.isInProgress, snapshot.startedAt != nil else {
            let entry = makeEntry(now, snapshot)
            let refresh = now.addingTimeInterval(900)
            return Timeline(entries: [entry], policy: .after(refresh))
        }

        var entries: [Entry] = [makeEntry(now, snapshot)]
        var nextDate = now.addingTimeInterval(refreshInterval)
        let endDate = now.addingTimeInterval(activeHorizon)

        while nextDate <= endDate {
            entries.append(makeEntry(nextDate, snapshot))
            nextDate = nextDate.addingTimeInterval(refreshInterval)
        }

        let policyDate = endDate.addingTimeInterval(refreshInterval)
        return Timeline(entries: entries, policy: .after(policyDate))
    }
}
