import Combine
import Foundation
import os

/// Coordinates scoring engine + persistence. Owns the single active match workflow.
@MainActor
public final class MatchService: ObservableObject {
    @Published public private(set) var activeMatch: MatchState?
    @Published public private(set) var archivedMatches: [MatchState] = []

    private let engine: ScoringEngine
    private let store: MatchStore
    private let logger = Logger(subsystem: "com.padelscore", category: "MatchService")
    private var syncHandler: ((MatchState?, [MatchState]) -> Void)?

    public init(store: MatchStore, engine: ScoringEngine = ScoringEngine()) {
        self.store = store
        self.engine = engine
        restore()
    }

    /// Optional callback invoked after every persistence write (used by WatchConnectivity).
    public func onSyncNeeded(_ handler: @escaping (MatchState?, [MatchState]) -> Void) {
        syncHandler = handler
    }

    public func restore() {
        do {
            activeMatch = try store.loadActiveMatch()
            archivedMatches = try store.loadArchivedMatches().filter { $0.status != .discarded }
            logger.info("Restored active=\(self.activeMatch != nil) archive=\(self.archivedMatches.count)")
            expireInactiveMatchIfNeeded()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            activeMatch = nil
            archivedMatches = []
        }
    }

    public func startMatch(settings: MatchSettings = .default) {
        guard activeMatch == nil else { return }
        let match = engine.startMatch(settings: settings)
        activeMatch = match
        persist()
        logger.info("Match started \(match.id.uuidString)")
    }

    public func awardPoint(to side: Side) {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.pointWon(side), to: match)
            activeMatch = match
            if match.status == .completed {
                finalizeActiveMatch()
            } else {
                persist()
                expireInactiveMatchIfNeeded()
            }
            logger.info("Point \(side.rawValue)")
        } catch {
            logger.error("Point failed: \(error.localizedDescription)")
        }
    }

    public func selectServer(_ side: Side) {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.selectServer(side), to: match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
            logger.info("Server selected \(side.rawValue)")
        } catch {
            logger.error("Select server failed: \(error.localizedDescription)")
        }
    }

    public func undoLastPoint() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.undo, to: match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
            logger.info("Undo")
        } catch {
            logger.error("Undo failed: \(error.localizedDescription)")
        }
    }

    public var canUndo: Bool {
        guard let match = activeMatch, match.status == .inProgress else { return false }
        return match.events.contains { $0.kind == .pointWon }
    }

    public func finishMatch() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.finish, to: match)
            activeMatch = match
            finalizeActiveMatch()
            logger.info("Match finished")
        } catch {
            logger.error("Finish failed: \(error.localizedDescription)")
        }
    }

    /// Ends or discards an in-progress match that has exceeded the inactivity timeout.
    public func expireInactiveMatchIfNeeded(at date: Date = Date()) {
        guard let match = activeMatch, match.isInactive(at: date) else { return }
        if match.hasScoredPoints {
            endMatchEarly()
            logger.info("Match expired due to inactivity (ended early)")
        } else {
            discardMatch()
            logger.info("Match expired due to inactivity (discarded)")
        }
    }

    public func endMatchEarly() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.endEarly, to: match)
            activeMatch = match
            finalizeActiveMatch()
            logger.info("Match ended early")
        } catch {
            logger.error("End early failed: \(error.localizedDescription)")
        }
    }

    public func discardMatch() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.discard, to: match)
            // Discarded matches are not shown in history.
            activeMatch = nil
            try store.saveActiveMatch(nil)
            notifySync()
            logger.info("Match discarded")
        } catch {
            logger.error("Discard failed: \(error.localizedDescription)")
        }
    }

    /// Clears the active-match presentation after the user dismisses the completion screen.
    public func acknowledgeCompletedMatch() {
        guard let match = activeMatch, match.status.isTerminal, match.status != .discarded else {
            activeMatch = nil
            try? store.saveActiveMatch(nil)
            notifySync()
            return
        }
        // Ensure archived, then clear active.
        if !archivedMatches.contains(where: { $0.id == match.id }) {
            try? store.archiveMatch(match)
            archivedMatches = (try? store.loadArchivedMatches()) ?? archivedMatches
        }
        activeMatch = nil
        try? store.saveActiveMatch(nil)
        notifySync()
    }

    /// Used by the phone when receiving Watch sync payloads.
    public func applyRemoteSnapshot(active: MatchState?, archive: [MatchState]) {
        activeMatch = active
        archivedMatches = archive.filter { $0.status != .discarded }
            .sorted { $0.startedAt > $1.startedAt }
        try? store.saveActiveMatch(active)
        try? store.replaceArchive(archivedMatches)
    }

    private func finalizeActiveMatch() {
        guard let match = activeMatch else { return }
        if match.status != .discarded {
            try? store.archiveMatch(match)
            archivedMatches = (try? store.loadArchivedMatches().filter { $0.status != .discarded }) ?? []
        }
        // Keep terminal match as active until user acknowledges Done (Watch completion screen).
        try? store.saveActiveMatch(match)
        notifySync()
    }

    private func persist() {
        do {
            try store.saveActiveMatch(activeMatch)
            notifySync()
        } catch {
            logger.error("Persist failed: \(error.localizedDescription)")
        }
    }

    private func notifySync() {
        syncHandler?(activeMatch, archivedMatches)
    }
}
