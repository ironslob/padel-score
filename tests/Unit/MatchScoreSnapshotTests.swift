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
    }

    func testSnapshotWhenNoActiveMatch() {
        let snapshot = MatchScoreSnapshot(from: nil)

        XCTAssertFalse(snapshot.isInProgress)
        XCTAssertEqual(snapshot.compactLabel, "No match")
    }

    func testSnapshotEncodesAndDecodes() throws {
        let snapshot = MatchScoreSnapshot(
            gameLeft: "40",
            gameRight: "30",
            setLeft: "5",
            setRight: "4",
            isInProgress: true,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MatchScoreSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
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

    func testModeConsequencesMentionExpectedBehavior() {
        XCTAssertTrue(DuringPlayAccessCopy.scoreOnlyConsequence.contains("Bevel"))
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
