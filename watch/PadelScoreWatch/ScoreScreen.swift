import SwiftUI

/// Shared Watch control chrome. System `.bordered` buttons default to a capsule
/// on watchOS; custom score controls already use this 12pt continuous rect.
enum WatchTheme {
    static let buttonCornerRadius: CGFloat = 12

    static var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
    }
}

extension View {
    func watchButtonBorderShape() -> some View {
        buttonBorderShape(.roundedRectangle(radius: WatchTheme.buttonCornerRadius))
    }
}

struct ScoreScreen: View {
    @EnvironmentObject private var service: MatchService
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let match: MatchState

    @State private var undoSide: Side?
    @State private var undoStartedAt: Date?
    @State private var undoClearTask: Task<Void, Never>?

    private var game: (left: String, right: String) { match.scoreScreenGameDisplay }
    private var games: (left: String, right: String) { match.scoreScreenSetDisplay }
    private var undoTimeout: TimeInterval { MatchSettings.quickUndoTimeoutSeconds }
    private var leftRole: String { match.servingRoleLabels.left }
    private var rightRole: String { match.servingRoleLabels.right }
    private var scoreSides: (left: Side, right: Side) { match.scoreScreenSides }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: undoStartedAt == nil || isLuminanceReduced
            )
        ) { context in
            let progress = undoProgress(at: context.date)

            VStack(spacing: isLuminanceReduced ? 6 : 10) {
                if match.currentGame.isTieBreak {
                    tieBreakHeader
                } else if match.currentGame.isGoldenPointActive {
                    decidingPointHeader
                } else {
                    gamesHeader
                }

                HStack(spacing: 8) {
                    scoreButton(
                        logicalSide: scoreSides.left,
                        score: game.left,
                        role: leftRole,
                        tint: teamTint(for: scoreSides.left),
                        showsServeIndicator: match.currentServer == scoreSides.left,
                        progress: isLuminanceReduced ? 0 : (undoSide == scoreSides.left ? progress : 0)
                    )
                    scoreButton(
                        logicalSide: scoreSides.right,
                        score: game.right,
                        role: rightRole,
                        tint: teamTint(for: scoreSides.right),
                        showsServeIndicator: match.currentServer == scoreSides.right,
                        progress: isLuminanceReduced ? 0 : (undoSide == scoreSides.right ? progress : 0)
                    )
                }
            }
            .padding(.horizontal, 4)
            .onChange(of: progress) { _, newValue in
                if newValue >= 1 {
                    clearUndoWindow()
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.8), trigger: match.events.count)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: match.activeTieBreakNotice)
        .onDisappear { clearUndoWindow() }
        .onChange(of: isLuminanceReduced) { _, reduced in
            if reduced {
                clearUndoWindow()
            }
        }
    }

    private func teamTint(for logicalSide: Side) -> Color {
        logicalSide == .left ? .blue : .red
    }

    private var setScoreFont: Font {
        if isLuminanceReduced {
            return .title2.weight(.bold).monospacedDigit()
        }
        return .title3.weight(.semibold).monospacedDigit()
    }

    @ViewBuilder
    private var tieBreakHeader: some View {
        if isLuminanceReduced {
            VStack(spacing: 2) {
                Text("TB")
                    .font(setScoreFont)
                    .foregroundStyle(.primary)
                if let notice = match.activeTieBreakNotice {
                    Text(tieBreakNoticeAbbreviation(notice))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tieBreakAccessibilityLabel)
        } else {
            VStack(spacing: 2) {
                Text("Tie-break")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text("\(games.left) – \(games.right)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let notice = match.activeTieBreakNotice {
                    Text(tieBreakNoticeLabel(notice))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("First to 7")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tieBreakAccessibilityLabel)
        }
    }

    private var tieBreakAccessibilityLabel: String {
        var parts = ["Tie-break, 6 games all"]
        if let notice = match.activeTieBreakNotice {
            parts.append(tieBreakNoticeLabel(notice))
        }
        return parts.joined(separator: ", ")
    }

    private func tieBreakNoticeLabel(_ notice: TieBreakNotice) -> String {
        switch notice {
        case .changeServe: return "Change serve"
        case .changeSides: return "Change sides"
        }
    }

    private func tieBreakNoticeAbbreviation(_ notice: TieBreakNotice) -> String {
        switch notice {
        case .changeServe: return "Serve"
        case .changeSides: return "Sides"
        }
    }

    @ViewBuilder
    private var gamesHeader: some View {
        let status = match.settings.deuceFormat.numbersDeuceCycles ? match.gameStatusLine : nil
        let gamesLabel = "Games \(games.left) to \(games.right)"
        if isLuminanceReduced || status == nil {
            Text("\(games.left) – \(games.right)")
                .font(setScoreFont)
                .foregroundStyle(.primary)
                .accessibilityLabel(
                    status.map { "\(gamesLabel), \($0)" } ?? gamesLabel
                )
        } else {
            VStack(spacing: 2) {
                Text("\(games.left) – \(games.right)")
                    .font(setScoreFont)
                    .foregroundStyle(.primary)
                Text(status!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(gamesLabel), \(status!)")
        }
    }

    @ViewBuilder
    private var decidingPointHeader: some View {
        let format = match.settings.deuceFormat
        let accessibility = "\(format.decidingPointLabel), next point wins"
        if isLuminanceReduced {
            Text(format.decidingPointShortLabel)
                .font(setScoreFont)
                .foregroundStyle(.primary)
                .accessibilityLabel(accessibility)
        } else {
            VStack(spacing: 2) {
                Text(format.decidingPointLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
                Text("Next point wins")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibility)
        }
    }

    private func scoreButton(
        logicalSide: Side,
        score: String,
        role: String,
        tint: Color,
        showsServeIndicator: Bool,
        progress: Double
    ) -> some View {
        Button {
            handleTap(logicalSide)
        } label: {
            ZStack {
                WatchTheme.buttonShape
                    .fill(tint.opacity(isLuminanceReduced ? 0.12 : 0.22))

                WatchTheme.buttonShape
                    .strokeBorder(tint.opacity(isLuminanceReduced ? 0.55 : 0.35), lineWidth: isLuminanceReduced ? 2.5 : 2)

                if progress > 0 {
                    ClockwiseRoundedRectOutline(progress: progress)
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }

                VStack(spacing: 2) {
                    Text(score)
                        .font(isLuminanceReduced ? .title.weight(.bold).monospacedDigit() : .title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    if !isLuminanceReduced {
                        Text(role)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, isLuminanceReduced ? 6 : 8)

                if showsServeIndicator {
                    Image(systemName: "tennisball.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isLuminanceReduced ? 64 : 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(serveAccessibilityLabel(role: role, score: score, isServing: showsServeIndicator))
        .accessibilityHint(
            undoSide == logicalSide
                ? "Double tap again to cancel the last point"
                : "Awards a point"
        )
    }

    private func serveAccessibilityLabel(role: String, score: String, isServing: Bool) -> String {
        isServing ? "\(role) \(score), serving" : "\(role) \(score)"
    }

    private func handleTap(_ logicalSide: Side) {
        if undoSide == logicalSide {
            service.undoLastPoint()
            clearUndoWindow()
            return
        }

        let previousMatch = service.activeMatch
        service.awardPoint(to: logicalSide)
        let updatedMatch = service.activeMatch

        // For points that end a game, we show a dedicated Game interstitial with undo
        // instead of keeping the in-button quick undo active.
        if !didPointEndGame(previous: previousMatch, updated: updatedMatch) {
            beginUndoWindow(for: logicalSide)
        } else {
            clearUndoWindow()
        }
    }

    private func beginUndoWindow(for side: Side) {
        undoClearTask?.cancel()
        undoSide = side
        undoStartedAt = Date()

        let timeout = undoTimeout
        undoClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            clearUndoWindow()
        }
    }

    private func clearUndoWindow() {
        undoClearTask?.cancel()
        undoClearTask = nil
        undoSide = nil
        undoStartedAt = nil
    }

    private func undoProgress(at date: Date) -> Double {
        guard let started = undoStartedAt, undoTimeout > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(started) / undoTimeout))
    }

    private func didPointEndGame(previous: MatchState?, updated: MatchState?) -> Bool {
        guard
            let previous,
            let updated,
            previous.status == .inProgress,
            updated.status == .inProgress
        else {
            return false
        }

        // A game boundary is visible as either:
        // - current set games increasing (regular game win), or
        // - completed sets increasing (set-clinching game).
        let previousGamesTotal = previous.currentSet.leftGames + previous.currentSet.rightGames
        let updatedGamesTotal = updated.currentSet.leftGames + updated.currentSet.rightGames
        if updatedGamesTotal > previousGamesTotal {
            return true
        }
        return updated.completedSets.count > previous.completedSets.count
    }
}

/// Draws a continuous rounded-rect stroke that grows clockwise from the top-center.
struct ClockwiseRoundedRectOutline: Shape {
    var progress: Double
    var cornerRadius: CGFloat = WatchTheme.buttonCornerRadius

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let full = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let fraction = max(0, min(1, progress))
        guard fraction > 0 else { return Path() }
        if fraction >= 1 { return full }

        let start = Self.topCenterStartFraction(rect: rect, radius: radius)
        return Self.trimmedWrapping(full, from: start, length: fraction)
    }

    /// `Path(roundedRect:)` starts at the top-leading end of the top edge, going clockwise.
    private static func topCenterStartFraction(rect: CGRect, radius: CGFloat) -> CGFloat {
        let straightWidth = max(0, rect.width - 2 * radius)
        let straightHeight = max(0, rect.height - 2 * radius)
        let perimeter = 2 * (straightWidth + straightHeight) + (2 * .pi * radius)
        guard perimeter > 0 else { return 0 }
        return (straightWidth / 2) / perimeter
    }

    private static func trimmedWrapping(_ path: Path, from start: CGFloat, length: CGFloat) -> Path {
        let end = start + length
        if end <= 1 {
            return path.trimmedPath(from: start, to: end)
        }
        var result = path.trimmedPath(from: start, to: 1)
        result.addPath(path.trimmedPath(from: 0, to: end - 1))
        return result
    }
}
