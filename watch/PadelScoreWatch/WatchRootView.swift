import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var service: MatchService
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGameInterstitial = false
    @State private var gameInterstitialCompletedSet = false
    @State private var gameInterstitialIsTieBreak = false
    @State private var gameInterstitialStartedAt: Date?
    @State private var gameInterstitialTask: Task<Void, Never>?
    @State private var scorePageToken = 0

    var body: some View {
        Group {
            if let match = service.activeMatch {
                switch match.status {
                case .inProgress:
                    if showGameInterstitial, let startedAt = gameInterstitialStartedAt {
                        GameInterstitialView(
                            match: match,
                            completedSet: gameInterstitialCompletedSet,
                            isTieBreak: gameInterstitialIsTieBreak,
                            startedAt: startedAt,
                            timeout: MatchSettings.quickUndoTimeoutSeconds,
                            onNext: clearGameInterstitial
                        )
                    } else if match.needsServerSelection {
                        SelectServerView()
                    } else {
                        ActiveMatchPager(match: match, scorePageToken: scorePageToken)
                    }
                case .completed, .endedEarly:
                    MatchCompleteView(match: match)
                case .discarded:
                    StartMatchView()
                }
            } else {
                StartMatchView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            sessionCoordinator.handleScenePhaseChange(newPhase)
        }
        .onChange(of: service.activeMatch) { oldMatch, newMatch in
            handleMatchChange(from: oldMatch, to: newMatch)
        }
        .onOpenURL { url in
            if url.scheme == "padelscore", url.host == "score" {
                scorePageToken += 1
            }
        }
        .alert("Workout tracking unavailable", isPresented: workoutErrorBinding) {
            Button("OK") { sessionCoordinator.dismissWorkoutError() }
        } message: {
            Text(sessionCoordinator.workoutErrorMessage ?? "")
        }
        .alert("Another workout is already active", isPresented: $sessionCoordinator.showWorkoutConflictPrompt) {
            Button("Use Score only") {
                sessionCoordinator.resolveWorkoutConflict(.switchToScoreOnly)
            }
            Button("Cancel match start", role: .destructive) {
                sessionCoordinator.resolveWorkoutConflict(.cancelMatchStart)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Apple Watch supports one active workout at a time. Keep this match as Score only, or cancel and end the other workout first.")
        }
        .alert("Quick tip", isPresented: $sessionCoordinator.showWristRaiseTip) {
            Button("Got it") { sessionCoordinator.dismissWristRaiseTip() }
        } message: {
            Text(DuringPlayAccessCopy.firstMatchTip)
        }
    }

    private func handleMatchChange(from oldMatch: MatchState?, to newMatch: MatchState?) {
        guard let oldMatch, let newMatch else {
            clearGameInterstitial()
            return
        }

        if let completedSet = didCompleteSet(from: oldMatch, to: newMatch) {
            let isTieBreak = newMatch.currentGame.isTieBreak && !oldMatch.currentGame.isTieBreak
            beginGameInterstitialWindow(
                completedSet: completedSet,
                isTieBreak: isTieBreak,
                timeout: MatchSettings.quickUndoTimeoutSeconds
            )
            return
        }

        // If an undo happens while interstitial is visible, drop it immediately.
        if showGameInterstitial && newMatch.events.count < oldMatch.events.count {
            clearGameInterstitial()
        }
    }

    private func didCompleteSet(from oldMatch: MatchState, to newMatch: MatchState) -> Bool? {
        guard oldMatch.status == .inProgress, newMatch.status == .inProgress else { return nil }
        guard newMatch.events.count > oldMatch.events.count else { return nil }
        guard newMatch.events.last?.kind == .pointWon else { return nil }

        let oldGamesTotal = oldMatch.currentSet.leftGames + oldMatch.currentSet.rightGames
        let newGamesTotal = newMatch.currentSet.leftGames + newMatch.currentSet.rightGames
        let setAdvanced = newMatch.completedSets.count > oldMatch.completedSets.count
        let gameAdvanced = newGamesTotal > oldGamesTotal
        guard setAdvanced || gameAdvanced else { return nil }
        return setAdvanced
    }

    private func beginGameInterstitialWindow(completedSet: Bool, isTieBreak: Bool, timeout: TimeInterval) {
        gameInterstitialTask?.cancel()
        gameInterstitialCompletedSet = completedSet
        gameInterstitialIsTieBreak = isTieBreak
        gameInterstitialStartedAt = Date()
        showGameInterstitial = true
        gameInterstitialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            clearGameInterstitial()
        }
    }

    private func clearGameInterstitial() {
        gameInterstitialTask?.cancel()
        gameInterstitialTask = nil
        showGameInterstitial = false
        gameInterstitialCompletedSet = false
        gameInterstitialIsTieBreak = false
        gameInterstitialStartedAt = nil
    }

    private var workoutErrorBinding: Binding<Bool> {
        Binding(
            get: { sessionCoordinator.workoutErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    sessionCoordinator.dismissWorkoutError()
                }
            }
        )
    }
}

private struct GameInterstitialView: View {
    @EnvironmentObject private var service: MatchService
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let match: MatchState
    let completedSet: Bool
    let isTieBreak: Bool
    let startedAt: Date
    let timeout: TimeInterval
    let onNext: () -> Void

    private var sets: (left: String, right: String) { match.matchSetsDisplay }
    private var games: (left: String, right: String) {
        if completedSet, let finishedSet = match.completedSets.last {
            return finishedSet.displayPair
        }
        return match.currentSet.displayPair
    }

    private var headline: String {
        if completedSet { return "Set!" }
        if isTieBreak { return "Tie-break" }
        return "Game!"
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: isLuminanceReduced
            )
        ) { context in
            let progress = nextProgress(at: context.date)

            VStack(spacing: 10) {
                Text(headline)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    if isTieBreak {
                        Text("First to 7, win by 2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Sets \(sets.left) – \(sets.right)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Games \(games.left) – \(games.right)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Button("Undo") {
                        service.undoLastPoint()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!service.canUndo)
                    .frame(maxWidth: .infinity)

                    nextButton(progress: isLuminanceReduced ? 0 : progress)
                }
            }
            .padding()
        }
    }

    private func nextButton(progress: Double) -> some View {
        let tint: Color = .green

        return Button(action: onNext) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isLuminanceReduced ? 0.12 : 0.22))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        tint.opacity(isLuminanceReduced ? 0.55 : 0.35),
                        lineWidth: isLuminanceReduced ? 2.5 : 2
                    )

                if progress > 0 {
                    ClockwiseRoundedRectOutline(progress: progress, cornerRadius: 12)
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }

                Text("Next")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next")
        .accessibilityHint("Continue to the next game")
    }

    private func nextProgress(at date: Date) -> Double {
        guard timeout > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / timeout))
    }
}

struct SelectServerView: View {
    @EnvironmentObject private var service: MatchService

    var body: some View {
        VStack(spacing: 10) {
            Text("Who's serving?")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button("We are") {
                service.selectServer(.left)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .frame(maxWidth: .infinity)

            Button("They are") {
                service.selectServer(.right)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

private enum StartMatchPhase {
    case idle
    case choosingGoldenPoint
}

struct StartMatchView: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @State private var phase: StartMatchPhase = .idle
    @State private var isStarting = false
    @State private var showDuringPlayHelp = false
    @State private var showSettings = false

    var body: some View {
        Group {
            switch phase {
            case .idle:
                idleContent
            case .choosingGoldenPoint:
                GoldenPointChoiceView(
                    isStarting: isStarting,
                    onChoice: { goldenPointEnabled in
                        Task { await startMatch(goldenPointEnabled: goldenPointEnabled) }
                    }
                )
            }
        }
        .padding()
        .sheet(isPresented: $showDuringPlayHelp) {
            DuringPlayHelpView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            Text("Padel Score")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button {
                phase = .choosingGoldenPoint
            } label: {
                Text("Start Match")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Start Match")

            Button("Settings") {
                showSettings = true
            }
            .font(.caption)
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Button("During play tips") {
                showDuringPlayHelp = true
            }
            .font(.caption)
            .buttonStyle(.plain)
            .accessibilityLabel("During play tips")
        }
    }

    private func startMatch(goldenPointEnabled: Bool) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await sessionCoordinator.startMatch(goldenPointEnabled: goldenPointEnabled)
    }
}

struct GoldenPointChoiceView: View {
    let isStarting: Bool
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Are you playing golden point?")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Are you playing golden point?")

            if isStarting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Button("Yes") {
                    onChoice(true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Yes, play golden point")

                Button("No") {
                    onChoice(false)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("No, use advantage and deuce only")
            }
        }
    }
}

struct DuringPlayHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(DuringPlayAccessCopy.helpSections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle(DuringPlayAccessCopy.helpTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Toggle(
                    "Us / Them labels",
                    isOn: Binding(
                        get: { sessionCoordinator.usThemLabels },
                        set: { sessionCoordinator.setUsThemLabels($0) }
                    )
                )
                Toggle(
                    "Server always on the left",
                    isOn: Binding(
                        get: { sessionCoordinator.fixedServerPositions },
                        set: { sessionCoordinator.setFixedServerPositions($0) }
                    )
                )
                Toggle(
                    "Always ask for serve at the start of a set",
                    isOn: Binding(
                        get: { sessionCoordinator.alwaysAskServeAtSetStart },
                        set: { sessionCoordinator.setAlwaysAskServeAtSetStart($0) }
                    )
                )
                .disabled(sessionCoordinator.fixedServerPositions)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum ActiveMatchPage: Int, Hashable {
    case score = 0
    case overview = 1
    case actions = 2
}

struct ActiveMatchPager: View {
    let match: MatchState
    let scorePageToken: Int

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage: ActiveMatchPage = .score

    var body: some View {
        TabView(selection: $selectedPage) {
            ScoreScreen(match: match)
                .tag(ActiveMatchPage.score)
            MatchOverviewScreen(match: match)
                .tag(ActiveMatchPage.overview)
            ActionsScreen(match: match)
                .tag(ActiveMatchPage.actions)
        }
        .tabViewStyle(.page(indexDisplayMode: isLuminanceReduced ? .never : .automatic))
        .onAppear {
            selectedPage = .score
        }
        .onChange(of: isLuminanceReduced) { _, reduced in
            if reduced {
                selectedPage = .score
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                selectedPage = .score
            }
        }
        .onChange(of: scorePageToken) { _, _ in
            selectedPage = .score
        }
    }
}
