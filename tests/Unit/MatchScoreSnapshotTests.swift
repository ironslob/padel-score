import Foundation
import XCTest

final class MatchScoreSnapshotTests: XCTestCase {
    func testSnapshotFromInProgressMatch() {
        let match = ScoringEngine().startMatch(settings: .default)

        let snapshot = MatchScoreSnapshot(from: match)

        XCTAssertTrue(snapshot.isInProgress)
        XCTAssertEqual(snapshot.gameLeft, "0")
        XCTAssertEqual(snapshot.gameRight, "0")
        XCTAssertEqual(snapshot.setLeft, "0")
        XCTAssertEqual(snapshot.setRight, "0")
        XCTAssertEqual(snapshot.gameLabel, "0–0")
        XCTAssertEqual(snapshot.setLabel, "0–0")
        XCTAssertEqual(snapshot.startedAt, match.startedAt)
        XCTAssertFalse(snapshot.isGoldenPointActive)
        XCTAssertFalse(snapshot.isTieBreak)
        XCTAssertNil(snapshot.gameStatusLine)
        XCTAssertNotNil(snapshot.elapsedLabel())
    }

    func testSnapshotWhenNoActiveMatch() {
        let snapshot = MatchScoreSnapshot(from: nil)

        XCTAssertFalse(snapshot.isInProgress)
        XCTAssertEqual(snapshot.compactLabel, "No match")
        XCTAssertNil(snapshot.startedAt)
        XCTAssertNil(snapshot.elapsedLabel())
    }

    func testSnapshotEncodesAndDecodes() throws {
        let snapshot = MatchScoreSnapshot(
            gameLeft: "40",
            gameRight: "30",
            setLeft: "5",
            setRight: "4",
            isInProgress: true,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            startedAt: Date(timeIntervalSince1970: 900),
            isGoldenPointActive: true,
            isTieBreak: false,
            gameStatusLine: "Golden Point"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MatchScoreSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotDecodesLegacyPayloadWithoutNewFields() throws {
        let legacyJSON = """
        {
            "gameLeft": "15",
            "gameRight": "0",
            "setLeft": "2",
            "setRight": "1",
            "isInProgress": true,
            "updatedAt": 1000
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MatchScoreSnapshot.self, from: data)

        XCTAssertEqual(decoded.gameLeft, "15")
        XCTAssertNil(decoded.startedAt)
        XCTAssertFalse(decoded.isGoldenPointActive)
        XCTAssertFalse(decoded.isTieBreak)
        XCTAssertNil(decoded.gameStatusLine)
    }

    func testSnapshotStoreRoundTrip() throws {
        let suiteName = "MatchScoreSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let snapshot = MatchScoreSnapshot(
            gameLeft: "40",
            gameRight: "30",
            setLeft: "4",
            setRight: "3",
            isInProgress: true,
            startedAt: Date(timeIntervalSince1970: 500)
        )

        MatchScoreSnapshotStore.save(snapshot, defaults: defaults)
        let loaded = MatchScoreSnapshotStore.load(defaults: defaults)

        XCTAssertEqual(loaded, snapshot)
    }
}

final class MatchLiveActivityLifecycleTests: XCTestCase {
    func testStartsWhenInProgressMatchAppears() {
        let match = ScoringEngine().startMatch(settings: .default)

        let action = MatchLiveActivityLifecycle.action(previousMatchID: nil, match: match)

        XCTAssertEqual(action, .start(match))
    }

    func testUpdatesWhenSameMatchChanges() throws {
        var match = ScoringEngine().startMatch(settings: .default)
        match = try ScoringEngine().apply(.selectServer(.left), to: match)
        match = try ScoringEngine().apply(.pointWon(.left), to: match)

        let action = MatchLiveActivityLifecycle.action(previousMatchID: match.id, match: match)

        XCTAssertEqual(action, .update(match))
    }

    func testEndsWhenMatchCompletes() {
        var match = ScoringEngine().startMatch(settings: .default)
        match.status = .completed

        let action = MatchLiveActivityLifecycle.action(previousMatchID: match.id, match: match)

        XCTAssertEqual(action, .end(dismissImmediately: false))
    }

    func testEndsImmediatelyWhenMatchDiscarded() {
        var match = ScoringEngine().startMatch(settings: .default)
        match.status = .discarded

        let action = MatchLiveActivityLifecycle.action(previousMatchID: match.id, match: match)

        XCTAssertEqual(action, .end(dismissImmediately: true))
    }

    func testEndsWhenMatchCleared() {
        let previousID = UUID()

        let action = MatchLiveActivityLifecycle.action(previousMatchID: previousID, match: nil)

        XCTAssertEqual(action, .end(dismissImmediately: true))
    }
}

final class WorkoutPauseResumeLogicTests: XCTestCase {
    func testPauseWhenRunning() {
        XCTAssertEqual(WorkoutPauseResumeLogic.action(isPaused: false), .pause)
    }

    func testResumeWhenPaused() {
        XCTAssertEqual(WorkoutPauseResumeLogic.action(isPaused: true), .resume)
    }
}

final class WristRaiseTipStoreTests: XCTestCase {
    func testTipShowsOnce() {
        let suiteName = "WristRaiseTipStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsWristRaiseTipStore(defaults: defaults)

        XCTAssertTrue(store.shouldShowTip)
        store.markTipSeen()
        XCTAssertFalse(store.shouldShowTip)
    }
}

final class WorkoutSessionErrorTests: XCTestCase {
    func testAnotherWorkoutMessage() {
        XCTAssertTrue(
            WorkoutSessionError.anotherWorkoutSessionActive.userMessage.contains("Another workout")
        )
    }
}

final class DuringPlayAccessCopyTests: XCTestCase {
    func testFirstMatchTipMentionsDock() {
        XCTAssertTrue(DuringPlayAccessCopy.firstMatchTip.contains("Dock"))
        XCTAssertTrue(DuringPlayAccessCopy.firstMatchTip.contains("swipe up"))
    }

    func testHelpSectionsAreNonEmpty() {
        XCTAssertFalse(DuringPlayAccessCopy.helpSections.isEmpty)
        XCTAssertTrue(DuringPlayAccessCopy.helpSections.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
    }

    func testHelpSectionsMentionSmartStack() {
        XCTAssertTrue(
            DuringPlayAccessCopy.helpSections.contains { $0.title == "Smart Stack" }
        )
        XCTAssertTrue(
            DuringPlayAccessCopy.helpSections.contains { $0.body.contains("Match Glance") }
        )
    }

    func testModeConsequencesMentionExpectedBehavior() {
        XCTAssertTrue(DuringPlayAccessCopy.scoreOnlyConsequence.contains("Health workout"))
        XCTAssertTrue(DuringPlayAccessCopy.trackAsWorkoutConsequence.contains("one workout"))
    }
}

final class WorkoutModePreferenceStoreTests: XCTestCase {
    func testPreferredModePersists() {
        let suiteName = "WorkoutModePreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsWorkoutModePreferenceStore(defaults: defaults)

        XCTAssertNil(store.preferredWorkoutTrackingModeRawValue)
        store.setPreferredWorkoutTrackingModeRawValue("trackAsWorkout")
        XCTAssertEqual(store.preferredWorkoutTrackingModeRawValue, "trackAsWorkout")
    }
}

final class ServeSelectionPreferenceStoreTests: XCTestCase {
    func testAlwaysAskServeAtSetStartDefaultsFalseAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.alwaysAskServeAtSetStart)
        store.setAlwaysAskServeAtSetStart(true)
        XCTAssertTrue(store.alwaysAskServeAtSetStart)
    }

    func testFixedServerPositionsDefaultsFalseAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.fixed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.fixedServerPositions)
        store.setFixedServerPositions(true)
        XCTAssertTrue(store.fixedServerPositions)
    }

    func testUsThemLabelsDefaultsFalseAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.usThem.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.usThemLabels)
        store.setUsThemLabels(true)
        XCTAssertTrue(store.usThemLabels)
    }
}
