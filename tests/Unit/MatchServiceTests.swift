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

    func testStartMatchPersistsGoldenPointSetting() {
        let store = InMemoryMatchStore()
        let service = MatchService(store: store)
        var settings = MatchSettings.default
        settings.goldenPointEnabled = false
        service.startMatch(settings: settings)
        XCTAssertEqual(service.activeMatch?.settings.goldenPointEnabled, false)
        XCTAssertEqual(store.active?.settings.goldenPointEnabled, false)
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

    private func serviceWithActiveMatch(_ match: MatchState) -> MatchService {
        let store = InMemoryMatchStore()
        store.active = match
        return MatchService(store: store)
    }
}
