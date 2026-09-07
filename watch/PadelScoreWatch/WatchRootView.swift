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
                            timeout: gameInterstitialCompletedSet ? 0 : MatchSettings.quickUndoTimeoutSeconds,
                            onNext: clearGameInterstitial,
                            onChooseServer: chooseServerForNextSet
                        )
                    } else if match.needsWarmUp {
                        WarmUpView(match: match)
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
        .alert(WorkoutConflictCopy.title, isPresented: $sessionCoordinator.showWorkoutConflictPrompt) {
            Button(WorkoutConflictCopy.continueWithoutWorkout) {
                sessionCoordinator.resolveWorkoutConflict(.continueWithoutWorkout)
            }
            Button(WorkoutConflictCopy.cancelMatchStart, role: .destructive) {
                sessionCoordinator.resolveWorkoutConflict(.cancelMatchStart)
            }
        } message: {
            Text(WorkoutConflictCopy.message)
        }
        .sheet(isPresented: $sessionCoordinator.showFirstLaunchTip, onDismiss: {
            sessionCoordinator.dismissFirstLaunchTip()
        }) {
            FirstLaunchTipView {
                sessionCoordinator.dismissFirstLaunchTip()
            }
        }
    }

    private func handleMatchChange(from oldMatch: MatchState?, to newMatch: MatchState?) {
        guard let oldMatch, let newMatch else {
            clearGameInterstitial()
            return
        }

        if let completedSet = didCompleteSet(from: oldMatch, to: newMatch) {
            let isTieBreak = newMatch.currentGame.isTieBreak && !oldMatch.currentGame.isTieBreak
            beginGameInterstitialWindow(completedSet: completedSet, isTieBreak: isTieBreak)
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

    private func beginGameInterstitialWindow(completedSet: Bool, isTieBreak: Bool) {
        gameInterstitialTask?.cancel()
        gameInterstitialTask = nil
        gameInterstitialCompletedSet = completedSet
        gameInterstitialIsTieBreak = isTieBreak
        gameInterstitialStartedAt = Date()
        showGameInterstitial = true

        // A finished set waits to be tapped through: ends get swapped and the serve
        // order rearranged long before anyone looks at their wrist again.
        guard !completedSet else { return }

        let timeout = MatchSettings.quickUndoTimeoutSeconds
        gameInterstitialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            clearGameInterstitial()
        }
    }

    /// Starts the next set by asking who serves, rather than carrying the rotation on.
    private func chooseServerForNextSet() {
        service.requestServerSelection()
        clearGameInterstitial()
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
    let onChooseServer: () -> Void

    @State private var confirmEndMatch = false

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

    private var nextLabel: String {
        completedSet ? "Next set" : "Next"
    }

    /// The changeover between sets is where ends get swapped and the serve order
    /// rearranged, so that is the only place a fresh serve choice is offered.
    private var offersServeChoice: Bool {
        completedSet && match.canChooseNewServer
    }

    var body: some View {
        Group {
            if completedSet {
                setEndContent
            } else {
                gameEndContent
            }
        }
        .confirmationDialog("End this match? The current score is kept.", isPresented: $confirmEndMatch) {
            Button("End Match", role: .destructive) { service.finishMatch() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Between games the likely actions fit on one row, and a countdown carries on
    /// if nobody taps.
    private var gameEndContent: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: isLuminanceReduced || timeout <= 0
            )
        ) { context in
            let progress = nextProgress(at: context.date)

            ScrollView {
                VStack(spacing: 10) {
                    scoreSummary

                    HStack(spacing: 8) {
                        undoButton
                        nextButton(progress: isLuminanceReduced ? 0 : progress)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
        }
    }

    /// Between sets there is time to look, so buttons stay full size and scroll in
    /// the order they are most likely needed: continue, new serve, undo, then stop.
    private var setEndContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                scoreSummary

                nextSetButton

                if offersServeChoice {
                    chooseServerButton
                }

                undoButton

                Button(role: .destructive) {
                    confirmEndMatch = true
                } label: {
                    Text("End match")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .watchButtonBorderShape()
                .accessibilityLabel("End match")
                .accessibilityHint("Finish the match and keep the current score")
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
    }

    private var scoreSummary: some View {
        VStack(spacing: 10) {
            Text(headline)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                if match.isMatchTieBreak {
                    Text("First to 10, win by 2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isTieBreak {
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
        }
    }

    private var undoButton: some View {
        Button {
            service.undoLastPoint()
        } label: {
            Text("Undo")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .watchButtonBorderShape()
        .tint(.orange)
        .disabled(!service.canUndo)
        .accessibilityLabel("Undo")
        .accessibilityHint("Remove the last point")
    }

    private var nextSetButton: some View {
        Button(action: onNext) {
            Text("Next set")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .watchButtonBorderShape()
        .accessibilityLabel("Next set")
        .accessibilityHint("Continue to the next set, keeping the serve rotation")
    }

    private var chooseServerButton: some View {
        Button(action: onChooseServer) {
            Text("New serve")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .watchButtonBorderShape()
        .accessibilityLabel("New serve")
        .accessibilityHint("Start the next set and choose who is serving")
    }

    private func nextButton(progress: Double) -> some View {
        let tint: Color = .green

        return Button(action: onNext) {
            ZStack {
                WatchTheme.buttonShape
                    .fill(tint.opacity(isLuminanceReduced ? 0.12 : 0.22))

                WatchTheme.buttonShape
                    .strokeBorder(
                        tint.opacity(isLuminanceReduced ? 0.55 : 0.35),
                        lineWidth: isLuminanceReduced ? 2.5 : 2
                    )

                if progress > 0 {
                    ClockwiseRoundedRectOutline(progress: progress)
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }

                Text(nextLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nextLabel)
        .accessibilityHint("Continue to the next game")
    }

    private func nextProgress(at date: Date) -> Double {
        guard timeout > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / timeout))
    }
}

struct SelectServerView: View {
    @EnvironmentObject private var service: MatchService

    /// Only the opening prompt sits on top of Start Match. Between sets the player
    /// still has to pick a server, otherwise scoring would be blocked.
    private var canReturnToStart: Bool {
        service.activeMatch?.isWaitingForFirstServe == true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Who's serving?")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Button {
                        service.selectServer(.left)
                    } label: {
                        Text("Us")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .watchButtonBorderShape()
                    .tint(.blue)
                    .accessibilityLabel("We are serving")
                    .accessibilityHint("Us starts the match on serve")

                    Button {
                        service.selectServer(.right)
                    } label: {
                        Text("Them")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .watchButtonBorderShape()
                    .tint(.red)
                    .accessibilityLabel("They are serving")
                    .accessibilityHint("Them starts the match on serve")
                }

                if canReturnToStart {
                    Button {
                        service.discardMatch()
                    } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .watchButtonBorderShape()
                    .accessibilityLabel("Back")
                    .accessibilityHint("Return to the start screen without starting the match")
                }
            }
            .padding()
        }
    }
}

struct StartMatchView: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @State private var isStarting = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Padel Score")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await startMatch() }
                } label: {
                    Group {
                        if isStarting {
                            ProgressView()
                        } else {
                            Text("Start Match")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .watchButtonBorderShape()
                .tint(.green)
                .disabled(isStarting)
                .accessibilityLabel("Start Match")

                Button {
                    showSettings = true
                } label: {
                    Text("Settings")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .watchButtonBorderShape()
                .accessibilityLabel("Settings")
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            sessionCoordinator.presentFirstLaunchTipIfNeeded()
        }
    }

    private func startMatch() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await sessionCoordinator.startMatch()
    }
}

struct FirstLaunchTipView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(FirstLaunchTipCopy.tipSections.enumerated()), id: \.offset) { _, section in
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
            .navigationTitle(FirstLaunchTipCopy.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { onDismiss() }
                }
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

struct MatchPreferenceToggles: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    var match: MatchState?
    var showsHelperText = false

    var body: some View {
        MatchSetFormatPicker(match: match, showsHelperText: showsHelperText)
        DeuceFormatPicker(match: match, showsHelperText: showsHelperText)
        PreferenceToggleRow(
            title: "Us / Them labels",
            helper: SettingsCopy.usThemLabels,
            showsHelper: showsHelperText,
            isOn: Binding(
                get: { match?.settings.usThemLabels ?? sessionCoordinator.usThemLabels },
                set: { sessionCoordinator.setUsThemLabels($0) }
            )
        )
        PreferenceToggleRow(
            title: "Swap sides each game",
            helper: SettingsCopy.fixedServerPositions,
            showsHelper: showsHelperText,
            isOn: Binding(
                get: {
                    !(match?.settings.fixedServerPositions ?? sessionCoordinator.fixedServerPositions)
                },
                set: { sessionCoordinator.setFixedServerPositions(!$0) }
            )
        )
        PreferenceToggleRow(
            title: "Always ask for serve at the start of a set",
            helper: SettingsCopy.askServeAtSetStart,
            showsHelper: showsHelperText,
            isOn: Binding(
                get: { match?.settings.askServeAtSetStart ?? sessionCoordinator.alwaysAskServeAtSetStart },
                set: { sessionCoordinator.setAlwaysAskServeAtSetStart($0) }
            )
        )
        if match == nil {
            WarmUpSettings(showsHelperText: showsHelperText)
        }
    }
}

struct WarmUpSettings: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    var showsHelperText = false

    private var limitOptions: [Int] {
        var options = MatchSettings.warmUpMinutePresets
        let current = sessionCoordinator.warmUpMinutes
        if !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    var body: some View {
        PreferenceToggleRow(
            title: "Warm up before match",
            helper: SettingsCopy.warmUp,
            showsHelper: showsHelperText,
            isOn: Binding(
                get: { sessionCoordinator.warmUpEnabled },
                set: { sessionCoordinator.setWarmUpEnabled($0) }
            )
        )
        if sessionCoordinator.warmUpEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Picker(
                    "Warm-up limit",
                    selection: Binding(
                        get: { sessionCoordinator.warmUpMinutes },
                        set: { sessionCoordinator.setWarmUpMinutes($0) }
                    )
                ) {
                    ForEach(limitOptions, id: \.self) { minutes in
                        Text(MatchSettings.warmUpMinutesLabel(minutes)).tag(minutes)
                    }
                }
                if showsHelperText {
                    Text(SettingsCopy.warmUpLimit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MatchSetFormatPicker: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    var match: MatchState?
    var showsHelperText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "Match length",
                selection: Binding(
                    get: { match?.settings.matchSetFormat ?? sessionCoordinator.matchSetFormat },
                    set: { sessionCoordinator.setMatchSetFormat($0) }
                )
            ) {
                ForEach(MatchSetFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            if showsHelperText {
                Text(SettingsCopy.matchSetFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(match != nil)
    }
}

struct DeuceFormatPicker: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    var match: MatchState?
    var showsHelperText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "Scoring at deuce",
                selection: Binding(
                    get: { match?.settings.deuceFormat ?? sessionCoordinator.deuceFormat },
                    set: { sessionCoordinator.setDeuceFormat($0) }
                )
            ) {
                ForEach(DeuceFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            if showsHelperText {
                Text(SettingsCopy.deuceFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let helper: String
    let showsHelper: Bool
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            if showsHelper {
                Text(helper)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDuringPlayHelp = false

    var body: some View {
        NavigationStack {
            List {
                Button("Tips") {
                    showDuringPlayHelp = true
                }
                .accessibilityLabel("Tips")

                MatchPreferenceToggles(showsHelperText: true)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showDuringPlayHelp) {
                DuringPlayHelpView()
            }
        }
    }
}

private enum ActiveMatchPage: Int, Hashable {
    case overview = 0
    case score = 1
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
            MatchOverviewScreen(match: match)
                .tag(ActiveMatchPage.overview)
            ScoreScreen(match: match)
                .tag(ActiveMatchPage.score)
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
