import Combine
import Foundation
import HealthKit
import os
import SwiftUI
import WidgetKit

/// Manages match session lifecycle, always-on hooks, and optional workout tracking.
@MainActor
public final class MatchSessionCoordinator: ObservableObject {
    public enum WorkoutConflictResolution {
        case switchToScoreOnly
        case cancelMatchStart
    }

    public enum WorkoutTrackingMode: String, CaseIterable, Identifiable {
        case scoreOnly
        case trackAsWorkout

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .scoreOnly: return "Score only"
            case .trackAsWorkout: return "Track as workout"
            }
        }

        public var consequenceCopy: String {
            switch self {
            case .scoreOnly: return DuringPlayAccessCopy.scoreOnlyConsequence
            case .trackAsWorkout: return DuringPlayAccessCopy.trackAsWorkoutConsequence
            }
        }
    }

    @Published public private(set) var workoutTrackingMode: WorkoutTrackingMode = .trackAsWorkout
    @Published public private(set) var isWorkoutSessionActive = false
    @Published public private(set) var isWorkoutPaused = false
    @Published public var workoutErrorMessage: String?
    @Published public var showWristRaiseTip = false
    @Published public var showWorkoutConflictPrompt = false

    private let service: MatchService
    private let workoutManager: WorkoutSessionManaging
    private let tipStore: WristRaiseTipStoring
    private let modeStore: WorkoutModePreferenceStoring
    private let logger = Logger(subsystem: "com.padelscore", category: "MatchSession")
    private var cancellables = Set<AnyCancellable>()
    private var inactivityTask: Task<Void, Never>?

    public init(
        service: MatchService,
        healthStore: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil,
        workoutManager: WorkoutSessionManaging? = nil,
        tipStore: WristRaiseTipStoring = UserDefaultsWristRaiseTipStore(),
        modeStore: WorkoutModePreferenceStoring = UserDefaultsWorkoutModePreferenceStore()
    ) {
        self.service = service
        self.workoutManager = workoutManager ?? HealthKitWorkoutSessionManager(healthStore: healthStore)
        self.tipStore = tipStore
        self.modeStore = modeStore
        self.workoutManager.pauseStateHandler = { [weak self] isPaused in
            self?.isWorkoutPaused = isPaused
        }
        bindService()
        publishSnapshot(for: service.activeMatch)
        rescheduleInactivityTimer(for: service.activeMatch)
    }

    public func setWorkoutTrackingMode(_ mode: WorkoutTrackingMode) {
        workoutTrackingMode = mode
        modeStore.setPreferredWorkoutTrackingModeRawValue(mode.rawValue)
    }

    public func startMatch(goldenPointEnabled: Bool) async {
        guard service.activeMatch == nil else { return }

        var settings = MatchSettings.default
        settings.goldenPointEnabled = goldenPointEnabled
        service.startMatch(settings: settings)
        publishSnapshot(for: service.activeMatch)

        await startWorkoutSession()

        if tipStore.shouldShowTip {
            showWristRaiseTip = true
            tipStore.markTipSeen()
        }
    }

    public func dismissWristRaiseTip() {
        showWristRaiseTip = false
    }

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            service.expireInactiveMatchIfNeeded()
            publishSnapshot(for: service.activeMatch)
            rescheduleInactivityTimer(for: service.activeMatch)
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    public func dismissWorkoutError() {
        workoutErrorMessage = nil
    }

    public func resolveWorkoutConflict(_ resolution: WorkoutConflictResolution) {
        showWorkoutConflictPrompt = false
        switch resolution {
        case .switchToScoreOnly:
            setWorkoutTrackingMode(.scoreOnly)
            workoutErrorMessage = "Switched to Score only mode. Match tracking continues."
        case .cancelMatchStart:
            service.discardMatch()
            workoutErrorMessage = nil
        }
    }

    private func bindService() {
        service.$activeMatch
            .sink { [weak self] match in
                guard let self else { return }
                self.publishSnapshot(for: match)
                self.handleActiveMatchChanged(match)
                self.rescheduleInactivityTimer(for: match)
            }
            .store(in: &cancellables)
    }

    private func rescheduleInactivityTimer(for match: MatchState?) {
        inactivityTask?.cancel()
        inactivityTask = nil
        guard let match, match.status == .inProgress else { return }

        let elapsed = Date().timeIntervalSince(match.lastScoringActivityAt)
        let remaining = MatchSettings.inactivityTimeoutSeconds - elapsed
        if remaining <= 0 {
            service.expireInactiveMatchIfNeeded()
            return
        }

        inactivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if Task.isCancelled { return }
            service.expireInactiveMatchIfNeeded()
        }
    }

    private func publishSnapshot(for match: MatchState?) {
        let snapshot = MatchScoreSnapshot(from: match)
        MatchScoreSnapshotStore.save(snapshot)
        #if os(watchOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func handleActiveMatchChanged(_ match: MatchState?) {
        guard let match else {
            Task { await endWorkoutSession(saveWorkout: false) }
            return
        }

        switch match.status {
        case .inProgress:
            break
        case .completed, .endedEarly:
            Task { await endWorkoutSession(saveWorkout: true) }
        case .discarded:
            Task { await endWorkoutSession(saveWorkout: false) }
        }
    }

    private func startWorkoutSession() async {
        do {
            try await workoutManager.startWorkout(
                activityType: .tennis,
                metadata: ["padel-score-match": "true"]
            )
            isWorkoutSessionActive = true
            workoutErrorMessage = nil
            logger.info("Workout session started")
        } catch let error as WorkoutSessionError {
            isWorkoutSessionActive = false
            if error == .anotherWorkoutSessionActive {
                showWorkoutConflictPrompt = true
                workoutErrorMessage = nil
            } else {
                workoutErrorMessage = error.userMessage
                setWorkoutTrackingMode(.scoreOnly)
            }
            logger.error("Workout start failed: \(error.userMessage)")
        } catch {
            isWorkoutSessionActive = false
            setWorkoutTrackingMode(.scoreOnly)
            workoutErrorMessage = "Could not start workout tracking. Score only mode is active."
            logger.error("Workout start failed: \(error.localizedDescription)")
        }
    }

    private func endWorkoutSession(saveWorkout: Bool) async {
        guard isWorkoutSessionActive || workoutManager.isRunning else { return }
        do {
            try await workoutManager.endWorkout(save: saveWorkout)
            isWorkoutSessionActive = false
            logger.info("Workout session ended save=\(saveWorkout)")
        } catch {
            isWorkoutSessionActive = false
            logger.error("Workout end failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Workout session abstraction

public protocol WorkoutSessionManaging: AnyObject {
    var isRunning: Bool { get }
    var isPaused: Bool { get }
    var pauseStateHandler: ((Bool) -> Void)? { get set }
    @MainActor func startWorkout(activityType: HKWorkoutActivityType, metadata: [String: String]) async throws
    @MainActor func endWorkout(save: Bool) async throws
    @MainActor func pauseWorkout()
    @MainActor func resumeWorkout()
}

@MainActor
public final class HealthKitWorkoutSessionManager: NSObject, WorkoutSessionManaging {
    public private(set) var isRunning = false
    public private(set) var isPaused = false
    public var pauseStateHandler: ((Bool) -> Void)?

    private let healthStore: HKHealthStore?
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var endContinuation: CheckedContinuation<Void, Error>?

    public init(healthStore: HKHealthStore?) {
        self.healthStore = healthStore
        super.init()
    }

    public func startWorkout(
        activityType: HKWorkoutActivityType,
        metadata: [String: String]
    ) async throws {
        guard let healthStore else { throw WorkoutSessionError.healthDataUnavailable }
        guard !isRunning else { return }

        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: [])

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        if !metadata.isEmpty {
            var hkMetadata: [String: Any] = [:]
            for (key, value) in metadata {
                hkMetadata[key] = value
            }
            builder.addMetadata(hkMetadata) { _, _ in }
        }

        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.startContinuation = continuation
            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { success, error in
                Task { @MainActor in
                    if let error {
                        self.startContinuation?.resume(throwing: error)
                        self.startContinuation = nil
                        return
                    }
                    if !success {
                        self.startContinuation?.resume(throwing: WorkoutSessionError.authorizationDenied)
                        self.startContinuation = nil
                    }
                }
            }
        }
    }

    public func endWorkout(save: Bool) async throws {
        guard isRunning, let session, let builder else {
            if isRunning {
                cleanup()
            }
            return
        }

        let endDate = Date()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.endContinuation = continuation
            session.end()
            builder.endCollection(withEnd: endDate) { _, error in
                Task { @MainActor in
                    if let error {
                        self.endContinuation?.resume(throwing: error)
                        self.endContinuation = nil
                        self.cleanup()
                        return
                    }

                    if save {
                        builder.finishWorkout { _, finishError in
                            Task { @MainActor in
                                if let finishError {
                                    self.endContinuation?.resume(throwing: finishError)
                                } else {
                                    self.endContinuation?.resume()
                                }
                                self.endContinuation = nil
                                self.cleanup()
                            }
                        }
                    } else {
                        builder.discardWorkout()
                        self.endContinuation?.resume()
                        self.endContinuation = nil
                        self.cleanup()
                    }
                }
            }
        }
    }

    public func pauseWorkout() {
        guard isRunning, !isPaused, let session else { return }
        session.pause()
        setPaused(true)
    }

    public func resumeWorkout() {
        guard isRunning, isPaused, let session else { return }
        session.resume()
        setPaused(false)
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        pauseStateHandler?(paused)
    }

    private func cleanup() {
        isRunning = false
        isPaused = false
        session = nil
        builder = nil
    }
}

extension HealthKitWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                isRunning = true
                setPaused(false)
                startContinuation?.resume()
                startContinuation = nil
            case .paused:
                setPaused(true)
            case .ended, .stopped:
                if fromState == .running || fromState == .paused {
                    // End handled by endWorkout.
                }
            default:
                break
            }
        }
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            isRunning = false
            let workoutError: WorkoutSessionError
            if let hkError = error as? HKError, hkError.code == .errorAnotherWorkoutSessionStarted {
                workoutError = .anotherWorkoutSessionActive
            } else {
                workoutError = .authorizationDenied
            }
            startContinuation?.resume(throwing: workoutError)
            startContinuation = nil
            endContinuation?.resume(throwing: workoutError)
            endContinuation = nil
            cleanup()
        }
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didGenerate event: HKWorkoutEvent
    ) {
        guard event.type == .pauseOrResumeRequest else { return }
        Task { @MainActor in
            switch WorkoutPauseResumeLogic.action(isPaused: isPaused) {
            case .pause:
                pauseWorkout()
            case .resume:
                resumeWorkout()
            }
        }
    }
}

extension HealthKitWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
