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
            WorkoutSessionError.anotherWorkoutSessionActive.userMessage.contains("raise your wrist")
        )
    }
}

final class SettingsCopyTests: XCTestCase {
    func testSettingHelpersAreNonEmpty() {
        XCTAssertFalse(SettingsCopy.deuceFormat.isEmpty)
        XCTAssertFalse(SettingsCopy.usThemLabels.isEmpty)
        XCTAssertFalse(SettingsCopy.fixedServerPositions.isEmpty)
        XCTAssertFalse(SettingsCopy.askServeAtSetStart.isEmpty)
        XCTAssertFalse(SettingsCopy.matchSetFormat.isEmpty)
        XCTAssertFalse(SettingsCopy.warmUp.isEmpty)
        XCTAssertFalse(SettingsCopy.warmUpLimit.isEmpty)
    }
}

final class FirstLaunchTipCopyTests: XCTestCase {
    func testFirstLaunchTipMentionsHealthAndSettings() {
        XCTAssertEqual(FirstLaunchTipCopy.title, "Before you start")
        XCTAssertTrue(
            FirstLaunchTipCopy.tipSections.contains { $0.title == "Health" && $0.body.contains("Health access") }
        )
        XCTAssertTrue(
            FirstLaunchTipCopy.tipSections.contains { $0.title == "Settings" && $0.body.contains("Settings") }
        )
    }

    func testTipSectionsAreNonEmpty() {
        XCTAssertFalse(FirstLaunchTipCopy.tipSections.isEmpty)
        XCTAssertTrue(FirstLaunchTipCopy.tipSections.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
    }
}

final class DuringPlayAccessCopyTests: XCTestCase {
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
}

final class WorkoutConflictCopyTests: XCTestCase {
    func testConflictPromptExplainsWristRaiseCost() {
        XCTAssertEqual(WorkoutConflictCopy.continueWithoutWorkout, "Track without workout")
        XCTAssertTrue(WorkoutConflictCopy.message.contains("raise your wrist"))
        XCTAssertTrue(WorkoutConflictCopy.genericFailureMessage.contains("raise your wrist"))
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

    func testFixedServerPositionsDefaultsTrueAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.fixed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.fixedServerPositions)
        store.setFixedServerPositions(false)
        XCTAssertFalse(store.fixedServerPositions)
    }

    func testUsThemLabelsDefaultsTrueAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.usThem.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.usThemLabels)
        store.setUsThemLabels(false)
        XCTAssertFalse(store.usThemLabels)
    }

    func testDeuceFormatDefaultsGoldenPointAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.deuceFormat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.deuceFormat, .goldenPoint)
        store.setDeuceFormat(.silverPoint)
        XCTAssertEqual(store.deuceFormat, .silverPoint)
        store.setDeuceFormat(.advantage)
        XCTAssertEqual(store.deuceFormat, .advantage)
    }

    func testDeuceFormatMigratesFromLegacyGoldenPointToggle() {
        let suiteName = "ServeSelectionPreferenceStoreTests.legacyDeuce.\(UUID().uuidString)"

        // Someone who switched the old toggle off wanted full advantage scoring.
        let offDefaults = UserDefaults(suiteName: suiteName + ".off")!
        offDefaults.set(false, forKey: "goldenPointEnabled")
        XCTAssertEqual(
            UserDefaultsServeSelectionPreferenceStore(defaults: offDefaults).deuceFormat,
            .advantage
        )

        // Everyone else lands on the new default.
        let onDefaults = UserDefaults(suiteName: suiteName + ".on")!
        onDefaults.set(true, forKey: "goldenPointEnabled")
        XCTAssertEqual(
            UserDefaultsServeSelectionPreferenceStore(defaults: onDefaults).deuceFormat,
            .goldenPoint
        )

        // An explicit choice always beats the legacy key.
        let bothDefaults = UserDefaults(suiteName: suiteName + ".both")!
        bothDefaults.set(false, forKey: "goldenPointEnabled")
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: bothDefaults)
        store.setDeuceFormat(.silverPoint)
        XCTAssertEqual(store.deuceFormat, .silverPoint)
    }

    func testArchivedMatchesKeepSilverPointBehaviour() throws {
        // Matches written before this setting existed played one advantage before
        // the decisive point, so they must decode as silver point, not golden.
        let legacy = """
        {"setsToWin":2,"gamesToWinSet":6,"mustWinByTwoGames":true,"goldenPointEnabled":true}
        """
        let settings = try JSONDecoder().decode(MatchSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.deuceFormat, .silverPoint)

        let legacyOff = """
        {"setsToWin":2,"gamesToWinSet":6,"mustWinByTwoGames":true,"goldenPointEnabled":false}
        """
        let offSettings = try JSONDecoder().decode(MatchSettings.self, from: Data(legacyOff.utf8))
        XCTAssertEqual(offSettings.deuceFormat, .advantage)
    }

    func testDefaultSettingsUseGoldenPoint() {
        XCTAssertEqual(MatchSettings.default.deuceFormat, .goldenPoint)
        XCTAssertEqual(MatchSettings().deuceFormat, .goldenPoint)
    }

    func testDeuceFormatRoundTripsThroughCoding() throws {
        // The legacy key is written alongside the new one, so a round trip must
        // still land on the explicit format rather than the migration fallback.
        for format in DeuceFormat.allCases {
            var settings = MatchSettings.default
            settings.deuceFormat = format
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(MatchSettings.self, from: data)
            XCTAssertEqual(decoded.deuceFormat, format)
        }
    }

    func testDeuceFormatChangesRoundTripThroughCoding() throws {
        let engine = ScoringEngine()
        var match = engine.startMatch()
        match = try engine.apply(.selectServer(.left), to: match)
        match = try engine.apply(.setDeuceFormat(.advantage), to: match)

        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)
        XCTAssertEqual(decoded.deuceFormatChanges, match.deuceFormatChanges)
        XCTAssertEqual(decoded.settings.deuceFormat, .advantage)
    }

    func testMatchWrittenBeforeMidMatchChangesDecodes() throws {
        // Older archives have no change list at all; they simply played throughout
        // under the format in their settings.
        let engine = ScoringEngine()
        let match = try engine.apply(.selectServer(.left), to: engine.startMatch())
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(match)
        ) as! [String: Any]
        json.removeValue(forKey: "deuceFormatChanges")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)
        XCTAssertTrue(decoded.deuceFormatChanges.isEmpty)
        XCTAssertEqual(decoded.settings.deuceFormat, match.settings.deuceFormat)
    }

    func testMatchSetFormatDefaultsBestOfThreeAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.matchSetFormat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.matchSetFormat, .bestOfThree)
        store.setMatchSetFormat(.continuous)
        XCTAssertEqual(store.matchSetFormat, .continuous)
        store.setMatchSetFormat(.bestOfFive)
        XCTAssertEqual(store.matchSetFormat, .bestOfFive)
    }

    func testWarmUpDefaultsOnWithNoLimitAndPersists() {
        let suiteName = "ServeSelectionPreferenceStoreTests.warmUp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsServeSelectionPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.warmUpEnabled)
        XCTAssertEqual(store.warmUpMinutes, 0)
        store.setWarmUpEnabled(false)
        store.setWarmUpMinutes(12)
        XCTAssertFalse(store.warmUpEnabled)
        XCTAssertEqual(store.warmUpMinutes, 12)
        store.setWarmUpMinutes(99)
        XCTAssertEqual(store.warmUpMinutes, 30)
        store.setWarmUpMinutes(0)
        XCTAssertEqual(store.warmUpMinutes, 0)
        store.setWarmUpMinutes(-4)
        XCTAssertEqual(store.warmUpMinutes, 0)
    }

    func testNextWarmUpMinutesCyclesPresets() {
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 0), 3)
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 3), 5)
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 5), 10)
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 10), 0)
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 4), 5)
        XCTAssertEqual(MatchSettings.nextWarmUpMinutes(after: 12), 0)
    }

    func testDefaultSettingsEnableUnlimitedWarmUp() {
        XCTAssertTrue(MatchSettings.default.warmUpEnabled)
        XCTAssertEqual(MatchSettings.default.warmUpMinutes, 0)
        XCTAssertTrue(MatchSettings.default.shouldWarmUp)
        XCTAssertFalse(MatchSettings.default.hasWarmUpLimit)
    }

    func testLegacySettingsDecodeWithoutWarmUpKeys() throws {
        let legacy = """
        {"setsToWin":2,"gamesToWinSet":6,"mustWinByTwoGames":true,"goldenPointEnabled":true}
        """
        let settings = try JSONDecoder().decode(MatchSettings.self, from: Data(legacy.utf8))
        XCTAssertFalse(settings.warmUpEnabled)
        XCTAssertEqual(settings.warmUpMinutes, 0)
    }

    func testWarmUpSettingsRoundTripThroughCoding() throws {
        var settings = MatchSettings.default
        settings.warmUpEnabled = false
        settings.warmUpMinutes = 8
        let decoded = try JSONDecoder().decode(
            MatchSettings.self,
            from: try JSONEncoder().encode(settings)
        )
        XCTAssertFalse(decoded.warmUpEnabled)
        XCTAssertEqual(decoded.warmUpMinutes, 8)
    }

    func testSnapshotUsesScoreScreenLayoutWhenSidesSwap() throws {
        let engine = ScoringEngine()
        var settings = MatchSettings.default
        settings.fixedServerPositions = false
        var match = engine.startMatch(settings: settings)
        match = try engine.apply(.selectServer(.left), to: match)
        for _ in 0..<4 {
            match = try engine.apply(.pointWon(.left), to: match)
        }
        match = try engine.apply(.pointWon(.left), to: match)
        match = try engine.apply(.pointWon(.right), to: match)
        match = try engine.apply(.pointWon(.right), to: match)
        XCTAssertEqual(match.currentServer, .right)
        XCTAssertEqual(match.scoreScreenGameDisplay.left, "30")
        XCTAssertEqual(match.scoreScreenGameDisplay.right, "15")

        let snapshot = MatchScoreSnapshot(from: match)
        XCTAssertEqual(snapshot.gameLeft, "30")
        XCTAssertEqual(snapshot.gameRight, "15")
    }

    func testLegacyMatchWithoutNeedsServerSelectionKeepsKnownServer() throws {
        let engine = ScoringEngine()
        var match = engine.startMatch()
        match = try engine.apply(.selectServer(.left), to: match)
        match = try engine.apply(.pointWon(.left), to: match)
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(match)
        ) as! [String: Any]
        json.removeValue(forKey: "needsServerSelection")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)
        XCTAssertEqual(decoded.currentServer, .left)
        XCTAssertFalse(decoded.needsServerSelection)
        XCTAssertEqual(decoded.currentGame.leftPoints, 1)
    }
}
