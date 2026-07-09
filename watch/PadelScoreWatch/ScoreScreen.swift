import SwiftUI

struct ScoreScreen: View {
    @EnvironmentObject private var service: MatchService
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let match: MatchState

    @State private var undoSide: Side?
    @State private var undoStartedAt: Date?
    @State private var undoClearTask: Task<Void, Never>?

    private var game: (left: String, right: String) { match.currentGame.displayPair }
    private var games: (left: String, right: String) { match.currentSet.displayPair }
    private var undoTimeout: TimeInterval { match.settings.undoTimeoutSeconds }
    private var leftRole: String { match.currentServer == .left ? "Serving" : "Receiving" }
    private var rightRole: String { match.currentServer == .right ? "Serving" : "Receiving" }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: undoStartedAt == nil || isLuminanceReduced
            )
        ) { context in
            let progress = undoProgress(at: context.date)

            VStack(spacing: isLuminanceReduced ? 6 : 10) {
                if match.currentGame.isGoldenPointActive {
                    goldenPointLabel
                } else {
                    Text("\(games.left) – \(games.right)")
                        .font(setScoreFont)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Games \(games.left) to \(games.right)")
                }

                HStack(spacing: 8) {
                    scoreButton(
                        side: .left,
                        score: game.left,
                        role: leftRole,
                        tint: .blue,
                        progress: isLuminanceReduced ? 0 : (undoSide == .left ? progress : 0)
                    )
                    scoreButton(
                        side: .right,
                        score: game.right,
                        role: rightRole,
                        tint: .red,
                        progress: isLuminanceReduced ? 0 : (undoSide == .right ? progress : 0)
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
        .onDisappear { clearUndoWindow() }
        .onChange(of: isLuminanceReduced) { _, reduced in
            if reduced {
                clearUndoWindow()
            }
        }
    }

    private var setScoreFont: Font {
        if isLuminanceReduced {
            return .title2.weight(.bold).monospacedDigit()
        }
        return .title3.weight(.semibold).monospacedDigit()
    }

    @ViewBuilder
    private var goldenPointLabel: some View {
        if isLuminanceReduced {
            Text("GP")
                .font(setScoreFont)
                .foregroundStyle(.primary)
                .accessibilityLabel("Golden Point, next point wins")
        } else {
            VStack(spacing: 2) {
                Text("Golden Point")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
                Text("Next point wins")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Golden Point, next point wins")
        }
    }

    private func scoreButton(
        side: Side,
        score: String,
        role: String,
        tint: Color,
        progress: Double
    ) -> some View {
        Button {
            handleTap(side)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isLuminanceReduced ? 0.12 : 0.22))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(isLuminanceReduced ? 0.55 : 0.35), lineWidth: isLuminanceReduced ? 2.5 : 2)

                if progress > 0 {
                    ClockwiseRoundedRectOutline(progress: progress, cornerRadius: 12)
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
            }
            .frame(maxWidth: .infinity, minHeight: isLuminanceReduced ? 64 : 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(role) \(score)")
        .accessibilityHint(
            undoSide == side
                ? "Double tap again to cancel the last point"
                : "Awards a point"
        )
    }

    private func handleTap(_ side: Side) {
        if undoSide == side {
            service.undoLastPoint()
            clearUndoWindow()
            return
        }

        let previousMatch = service.activeMatch
        service.awardPoint(to: side)
        let updatedMatch = service.activeMatch

        // For points that end a game, we show a dedicated Game interstitial with undo
        // instead of keeping the in-button quick undo active.
        if !didPointEndGame(previous: previousMatch, updated: updatedMatch) {
            beginUndoWindow(for: side)
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

/// Draws a rounded-rect stroke that grows clockwise from the top-center.
private struct ClockwiseRoundedRectOutline: Shape {
    var progress: Double
    var cornerRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let full = roundedRectPath(in: rect, cornerRadius: radius)
        return full.trimmedPath(from: 0, to: max(0, min(1, progress)))
    }

    /// Path ordered from top-center, then clockwise around the rect.
    private func roundedRectPath(in rect: CGRect, cornerRadius r: CGFloat) -> Path {
        let midX = rect.midX
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: midX, y: minY))

        // Top edge → top-trailing corner
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(
            center: CGPoint(x: maxX - r, y: minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Trailing edge → bottom-trailing corner
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(
            center: CGPoint(x: maxX - r, y: maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge → bottom-leading corner
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addArc(
            center: CGPoint(x: minX + r, y: maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Leading edge → top-leading corner
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(
            center: CGPoint(x: minX + r, y: minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Back to top-center
        path.addLine(to: CGPoint(x: midX, y: minY))
        return path
    }
}
