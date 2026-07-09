import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var service: MatchService
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGameInterstitial = false
    @State private var gameInterstitialCompletedSet = false
    @State private var gameInterstitialTask: Task<Void, Never>?

    private let gameInterstitialSeconds: TimeInterval = 3

    var body: some View {
        Group {
            if let match = service.activeMatch {
                switch match.status {
                case .inProgress:
                    if showGameInterstitial {
                        GameInterstitialView(match: match, completedSet: gameInterstitialCompletedSet)
                    } else if match.needsServerSelection {
                        SelectServerView()
                    } else {
                        ActiveMatchPager(match: match)
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
            beginGameInterstitialWindow(completedSet: completedSet)
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

    private func beginGameInterstitialWindow(completedSet: Bool) {
        gameInterstitialTask?.cancel()
        gameInterstitialCompletedSet = completedSet
        showGameInterstitial = true
        gameInterstitialTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(gameInterstitialSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            showGameInterstitial = false
            gameInterstitialTask = nil
        }
    }

    private func clearGameInterstitial() {
        gameInterstitialTask?.cancel()
        gameInterstitialTask = nil
        showGameInterstitial = false
        gameInterstitialCompletedSet = false
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
    let match: MatchState
    let completedSet: Bool

    private var sets: (left: String, right: String) { match.matchSetsDisplay }
    private var games: (left: String, right: String) {
        if completedSet, let finishedSet = match.completedSets.last {
            return finishedSet.displayPair
        }
        return match.currentSet.displayPair
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(completedSet ? "Set!" : "Game!")
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("Sets \(sets.left) – \(sets.right)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Games \(games.left) – \(games.right)")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Button("Undo") {
                service.undoLastPoint()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!service.canUndo)
        }
        .padding()
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

struct StartMatchView: View {
    @EnvironmentObject private var sessionCoordinator: MatchSessionCoordinator
    @State private var isStarting = false
    @State private var showDuringPlayHelp = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Padel Score")
                .font(.headline)
                .multilineTextAlignment(.center)

            Picker("Mode", selection: workoutModeBinding) {
                ForEach(MatchSessionCoordinator.WorkoutTrackingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.navigationLink)

            Text(sessionCoordinator.workoutTrackingMode.consequenceCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await startMatch() }
            } label: {
                Group {
                    if isStarting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Start Match")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isStarting)
            .accessibilityLabel("Start Match")

            Button("During play tips") {
                showDuringPlayHelp = true
            }
            .font(.caption)
            .buttonStyle(.plain)
            .accessibilityLabel("During play tips")
        }
        .padding()
        .sheet(isPresented: $showDuringPlayHelp) {
            DuringPlayHelpView()
        }
    }

    private var workoutModeBinding: Binding<MatchSessionCoordinator.WorkoutTrackingMode> {
        Binding(
            get: { sessionCoordinator.workoutTrackingMode },
            set: { sessionCoordinator.setWorkoutTrackingMode($0) }
        )
    }

    private func startMatch() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await sessionCoordinator.startMatch()
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

private enum ActiveMatchPage: Int, Hashable {
    case score = 0
    case overview = 1
    case actions = 2
}

struct ActiveMatchPager: View {
    let match: MatchState

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
    }
}
