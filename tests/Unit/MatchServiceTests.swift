import Foundation
import XCTest

@MainActor
final class MatchServiceTests: XCTestCase {
    func testPersistAndRestoreActiveMatch() async throws {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        XCTAssertNotNil(store.active)
        XCTAssertEqual(store.active?.currentGame.leftPoints, 1)

        let restored = MatchService(store: store)
        XCTAssertEqual(restored.activeMatch?.currentGame.leftPoints, 1)
        XCTAssertEqual(restored.activeMatch?.id, service.activeMatch?.id)
    }

    func testFileStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileMatchStore(directory: dir)
        let engine = ScoringEngine()
        var match = engine.startMatch()
        match = try engine.apply(.selectServer(.left), to: match)
        match = try engine.apply(.pointWon(.right), to: match)
        try store.saveActiveMatch(match)

        let loaded = try store.loadActiveMatch()
        XCTAssertEqual(loaded?.currentGame.rightPoints, 1)

        match = try engine.apply(.endEarly, to: match)
        try store.saveActiveMatch(nil)
        try store.archiveMatch(match)
        let archive = try store.loadArchivedMatches()
        XCTAssertEqual(archive.count, 1)
        XCTAssertEqual(archive.first?.status, .endedEarly)
    }

    func testDiscardDoesNotArchive() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        service.discardMatch()
        XCTAssertNil(service.activeMatch)
        XCTAssertTrue(service.archivedMatches.isEmpty)
        XCTAssertNil(store.active)
    }

    func testDiscardBeforeServerSelectionClearsActiveMatch() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        XCTAssertEqual(service.activeMatch?.isWaitingForFirstServe, true)
        service.discardMatch()
        XCTAssertNil(service.activeMatch)
        XCTAssertTrue(service.archivedMatches.isEmpty)
        XCTAssertNil(store.active)
    }

    func testEndEarlyArchivesAndKeepsActiveUntilAck() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        service.endMatchEarly()
        XCTAssertEqual(service.activeMatch?.status, .endedEarly)
        XCTAssertEqual(service.archivedMatches.count, 1)
        service.acknowledgeCompletedMatch()
        XCTAssertNil(service.activeMatch)
        XCTAssertEqual(service.archivedMatches.count, 1)
    }

    func testUndoViaService() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        service.awardPoint(to: .right)
        service.undoLastPoint()
        XCTAssertEqual(service.activeMatch?.currentGame.leftPoints, 1)
        XCTAssertEqual(service.activeMatch?.currentGame.rightPoints, 0)
    }

    func testSelectingServerUpdatesActiveMatch() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        XCTAssertEqual(service.activeMatch?.needsServerSelection, true)
        service.selectServer(.right)
        XCTAssertEqual(service.activeMatch?.needsServerSelection, false)
        XCTAssertEqual(service.activeMatch?.currentServer, .right)
    }

    func testCompleteWarmUpPersistsAndKeepsServePrompt() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        XCTAssertEqual(service.activeMatch?.needsWarmUp, true)
        XCTAssertEqual(service.activeMatch?.needsServerSelection, true)
        service.completeWarmUp()
        XCTAssertEqual(service.activeMatch?.needsWarmUp, false)
        XCTAssertEqual(service.activeMatch?.needsServerSelection, true)
        XCTAssertEqual(store.active?.needsWarmUp, false)
    }

    func testNewServeAtTheChangeoverPromptsAndPersists() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        var settings = MatchSettings.default
        settings.setsToWin = 2
        service.startMatch(settings: settings)
        service.selectServer(.left)
        for _ in 0..<24 {
            service.awardPoint(to: .left) // 6-0, set to Us
        }
        XCTAssertEqual(service.activeMatch?.completedSets.count, 1)

        service.requestServerSelection()
        XCTAssertEqual(service.activeMatch?.needsServerSelection, true)
        XCTAssertEqual(store.active?.needsServerSelection, true)

        service.selectServer(.right)
        XCTAssertEqual(service.activeMatch?.currentServer, .right)
        service.awardPoint(to: .left)
        XCTAssertEqual(service.activeMatch?.currentServer, .right)
        XCTAssertEqual(store.active?.currentGame.leftPoints, 1)
    }

    func testStartMatchPersistsDeuceFormat() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        var settings = MatchSettings.default
        settings.deuceFormat = .silverPoint
        service.startMatch(settings: settings)
        XCTAssertEqual(service.activeMatch?.settings.deuceFormat, .silverPoint)
        XCTAssertEqual(store.active?.settings.deuceFormat, .silverPoint)
    }

    func testDeuceFormatCanBeChangedMidMatchAndPersists() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        var settings = MatchSettings.default
        settings.deuceFormat = .advantage
        service.startMatch(settings: settings)
        service.selectServer(.left)
        for _ in 0..<3 {
            service.awardPoint(to: .left)
            service.awardPoint(to: .right)
        }
        XCTAssertEqual(service.activeMatch?.gameStatusLine, "Deuce")

        service.setDeuceFormat(.goldenPoint)
        XCTAssertEqual(service.activeMatch?.settings.deuceFormat, .goldenPoint)
        XCTAssertEqual(service.activeMatch?.currentGame.isGoldenPointActive, true)
        XCTAssertEqual(store.active?.settings.deuceFormat, .goldenPoint)

        service.awardPoint(to: .left)
        XCTAssertEqual(service.activeMatch?.currentSet.leftGames, 1)
    }

    func testDeuceFormatChangeIgnoredWithoutAnActiveMatch() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.setDeuceFormat(.advantage)
        XCTAssertNil(service.activeMatch)
    }

    func testExpireInactiveMatchWithPointsEndsEarly() throws {
        let engine = ScoringEngine()
        let oldDate = Date(timeIntervalSinceNow: -31 * 60)
        var match = engine.startMatch(at: oldDate)
        match = try engine.apply(.selectServer(.left), to: match, at: oldDate)
        match = try engine.apply(.pointWon(.left), to: match, at: oldDate)

        let service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        XCTAssertEqual(service.activeMatch?.status, .endedEarly)
        XCTAssertEqual(service.archivedMatches.count, 1)
    }

    func testExpireInactiveMatchWithRecentPointStaysInProgress() throws {
        let engine = ScoringEngine()
        let startDate = Date(timeIntervalSinceNow: -60 * 60)
        let recentDate = Date(timeIntervalSinceNow: -5 * 60)
        var match = engine.startMatch(at: startDate)
        match = try engine.apply(.selectServer(.left), to: match, at: startDate)
        match = try engine.apply(.pointWon(.left), to: match, at: recentDate)

        let service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        XCTAssertEqual(service.activeMatch?.status, .inProgress)
        XCTAssertTrue(service.archivedMatches.isEmpty)
    }

    func testExpireInactiveZeroPointMatchDiscards() throws {
        let engine = ScoringEngine()
        let oldDate = Date(timeIntervalSinceNow: -31 * 60)
        let match = engine.startMatch(at: oldDate)

        let service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        XCTAssertNil(service.activeMatch)
        XCTAssertTrue(service.archivedMatches.isEmpty)
    }

    func testExpireInactiveRecentZeroPointMatchStaysInProgress() throws {
        let engine = ScoringEngine()
        let recentDate = Date(timeIntervalSinceNow: -5 * 60)
        let match = engine.startMatch(at: recentDate)

        let service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        XCTAssertEqual(service.activeMatch?.status, .inProgress)
    }

    func testRestoreExpiresInactiveMatch() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        let oldDate = Date(timeIntervalSinceNow: -31 * 60)
        var match = engine.startMatch(at: oldDate)
        match = try engine.apply(.selectServer(.left), to: match, at: oldDate)
        match = try engine.apply(.pointWon(.left), to: match, at: oldDate)
        store.active = match

        let service = MatchService(store: store)

        XCTAssertEqual(service.activeMatch?.status, .endedEarly)
        XCTAssertEqual(service.archivedMatches.count, 1)
    }

    func testUndoAllPointsOnInactiveMatchDiscards() throws {
        let engine = ScoringEngine()
        let startDate = Date(timeIntervalSinceNow: -31 * 60)
        let recentDate = Date(timeIntervalSinceNow: -5 * 60)
        var match = engine.startMatch(at: startDate)
        match = try engine.apply(.selectServer(.left), to: match, at: startDate)
        match = try engine.apply(.pointWon(.left), to: match, at: recentDate)

        let service = serviceWithActiveMatch(match)
        service.undoLastPoint()

        XCTAssertNil(service.activeMatch)
        XCTAssertTrue(service.archivedMatches.isEmpty)
    }

    func testDeleteArchivedMatchRemovesItAndRecordsTombstone() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        service.endMatchEarly()
        service.acknowledgeCompletedMatch()
        let id = try! XCTUnwrap(service.archivedMatches.first?.id)

        service.deleteArchivedMatch(id: id)

        XCTAssertTrue(service.archivedMatches.isEmpty)
        XCTAssertTrue(store.archive.isEmpty)
        XCTAssertEqual(store.deletedIDs, [id])
    }

    func testDeletedMatchDoesNotReturnViaRemoteSnapshot() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        var match = engine.startMatch()
        match = try engine.apply(.selectServer(.left), to: match)
        match = try engine.apply(.pointWon(.left), to: match)
        match = try engine.apply(.endEarly, to: match)
        store.archive = [match]

        let service = MatchService(store: store)
        service.deleteArchivedMatch(id: match.id)

        // The Watch is unaware and pushes its full archive back.
        service.applyRemoteSnapshot(active: nil, archive: [match])

        XCTAssertTrue(service.archivedMatches.isEmpty)
        XCTAssertTrue(store.archive.isEmpty)
    }

    func testDeletedMatchStaysDeletedAcrossRestore() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        var match = engine.startMatch()
        match = try engine.apply(.endEarly, to: match)
        store.archive = [match]

        let service = MatchService(store: store)
        service.deleteArchivedMatch(id: match.id)

        let restored = MatchService(store: store)
        XCTAssertTrue(restored.archivedMatches.isEmpty)
        XCTAssertEqual(restored.deletedMatchIDs, [match.id])
    }

    func testDeleteIgnoresTheActiveMatch() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        service.startMatch()
        service.selectServer(.left)
        service.awardPoint(to: .left)
        service.endMatchEarly()
        let id = try! XCTUnwrap(service.activeMatch?.id)

        service.deleteArchivedMatch(id: id)

        XCTAssertEqual(service.archivedMatches.count, 1)
        XCTAssertTrue(service.deletedMatchIDs.isEmpty)
    }

    func testRemoteDeletionsPruneArchiveButNotActiveMatch() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        var archived = engine.startMatch()
        archived = try engine.apply(.endEarly, to: archived)
        store.archive = [archived]

        let service = MatchService(store: store)
        service.startMatch()
        let activeID = try XCTUnwrap(service.activeMatch?.id)

        service.applyRemoteDeletions([archived.id, activeID])

        XCTAssertTrue(service.archivedMatches.isEmpty)
        XCTAssertTrue(store.archive.isEmpty)
        XCTAssertEqual(service.activeMatch?.id, activeID)
        XCTAssertEqual(service.deletedMatchIDs, [archived.id])
        XCTAssertEqual(store.deletedIDs, [archived.id])
    }

    func testDeletedIDsSurviveFileStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileMatchStore(directory: dir)
        XCTAssertTrue(try store.loadDeletedMatchIDs().isEmpty)

        let ids: Set<UUID> = [UUID(), UUID()]
        try store.saveDeletedMatchIDs(ids)

        XCTAssertEqual(try FileMatchStore(directory: dir).loadDeletedMatchIDs(), ids)
    }

    func testNoteIsStoredTrimmedAndClearedWhenBlank() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        let match = try engine.apply(.endEarly, to: engine.startMatch())
        store.archive = [match]
        let service = MatchService(store: store)

        service.setNote("  Played with Sam, windy court\n", for: match.id)
        XCTAssertEqual(service.note(for: match.id), "Played with Sam, windy court")
        XCTAssertEqual(store.notes[match.id], "Played with Sam, windy court")

        service.setNote("   ", for: match.id)
        XCTAssertEqual(service.note(for: match.id), "")
        XCTAssertNil(store.notes[match.id])
    }

    func testNoteSurvivesRemoteSnapshotAndRestore() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        let match = try engine.apply(.endEarly, to: engine.startMatch())
        store.archive = [match]
        let service = MatchService(store: store)
        service.setNote("Left knee sore", for: match.id)

        service.applyRemoteSnapshot(active: nil, archive: [match])
        XCTAssertEqual(service.note(for: match.id), "Left knee sore")

        let restored = MatchService(store: store)
        XCTAssertEqual(restored.note(for: match.id), "Left knee sore")
    }

    func testDeletingAMatchDropsItsNoteForGood() throws {
        let store = InMemoryMatchStore()
        let engine = ScoringEngine()
        let match = try engine.apply(.endEarly, to: engine.startMatch())
        store.archive = [match]
        let service = MatchService(store: store)
        service.setNote("Best of the season", for: match.id)

        service.deleteArchivedMatch(id: match.id)
        XCTAssertTrue(store.notes.isEmpty)

        // A detail view saving its draft on dismissal must not bring the note back.
        service.setNote("Best of the season", for: match.id)
        XCTAssertTrue(service.matchNotes.isEmpty)
    }

    func testNotesSurviveFileStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileMatchStore(directory: dir)
        XCTAssertTrue(try store.loadMatchNotes().isEmpty)

        let notes = [UUID(): "First note", UUID(): "Second note"]
        try store.saveMatchNotes(notes)

        XCTAssertEqual(try FileMatchStore(directory: dir).loadMatchNotes(), notes)
    }

    private func serviceWithActiveMatch(_ match: MatchState) -> MatchService {
        let store = InMemoryMatchStore()
        store.active = match
        return MatchService(store: store)
    }
}
