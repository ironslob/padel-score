import Combine
import Foundation
import os

/// Coordinates scoring engine + persistence. Owns the single active match workflow.
@MainActor
public final class MatchService: ObservableObject {
    @Published public private(set) var activeMatch: MatchState?
    @Published public private(set) var archivedMatches: [MatchState] = []
    @Published public private(set) var deletedMatchIDs: Set<UUID> = []
    @Published public private(set) var matchNotes: [UUID: String] = [:]
    @Published public private(set) var isRestored = false

    private let engine: ScoringEngine
    private let store: MatchStore
    private let logger = Logger(subsystem: "com.wristrally", category: "MatchService")
    private var syncHandler: ((MatchState?, [MatchState], Set<UUID>) -> Void)?

    public init(store: MatchStore, engine: ScoringEngine = ScoringEngine(), autoRestore: Bool = true) {
        self.store = store
        self.engine = engine
        if autoRestore {
            restore()
        }
    }

    /// Optional callback invoked after every persistence write (used by WatchConnectivity).
    public func onSyncNeeded(_ handler: @escaping (MatchState?, [MatchState], Set<UUID>) -> Void) {
        syncHandler = handler
    }

    public func restore() {
        do {
            deletedMatchIDs = try store.loadDeletedMatchIDs()
            matchNotes = try store.loadMatchNotes()
            activeMatch = try store.loadActiveMatch().map { engine.rehydrate($0) }
            archivedMatches = visibleArchive((try store.loadArchivedMatches()).map { engine.rehydrate($0) })
            logger.info("Restored active=\(self.activeMatch != nil) archive=\(self.archivedMatches.count)")
            finishRestore()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            activeMatch = nil
            archivedMatches = []
            isRestored = true
        }
    }

    public func restore() async {
        do {
            let store = self.store
            let (active, archive, deleted, notes) = try await Task.detached(priority: .userInitiated) {
                let active = try store.loadActiveMatch()
                let archive = try store.loadArchivedMatches()
                let deleted = try store.loadDeletedMatchIDs()
                let notes = try store.loadMatchNotes()
                return (active, archive, deleted, notes)
            }.value
            deletedMatchIDs = deleted
            matchNotes = notes
            activeMatch = active.map { engine.rehydrate($0) }
            archivedMatches = visibleArchive(archive.map { engine.rehydrate($0) })
            logger.info("Restored active=\(self.activeMatch != nil) archive=\(self.archivedMatches.count)")
            finishRestore()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            activeMatch = nil
            archivedMatches = []
            isRestored = true
        }
    }

    private func finishRestore() {
        isRestored = true
        expireInactiveMatchIfNeeded()
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

    /// Asks who serves the set about to start, instead of carrying the rotation on.
    /// Offered at the changeover, where players often swap ends and reorder the serve.
    public func requestServerSelection() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.requestServerSelection, to: match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
            logger.info("Server selection requested")
        } catch {
            logger.error("Server selection request failed: \(error.localizedDescription)")
        }
    }

    /// Ends the pre-match warm-up so the player can choose who serves.
    public func completeWarmUp() {
        guard var match = activeMatch, match.status == .inProgress else { return }
        do {
            match = try engine.apply(.completeWarmUp, to: match)
            activeMatch = match
            persist()
            logger.info("Warm-up completed")
        } catch {
            logger.error("Complete warm-up failed: \(error.localizedDescription)")
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

    /// Switches how games are decided at 40-40 part-way through a match, for when the
    /// wrong format was picked at the start. Applies from the current point on; games
    /// already played keep the result they were scored with.
    public func setDeuceFormat(_ format: DeuceFormat) {
        guard var match = activeMatch, match.status == .inProgress else { return }
        guard match.settings.deuceFormat != format else { return }
        do {
            match = try engine.apply(.setDeuceFormat(format), to: match)
            activeMatch = match
            persist()
            logger.info("Deuce format changed to \(format.rawValue)")
        } catch {
            logger.error("Deuce format change failed: \(error.localizedDescription)")
        }
    }

    /// Updates in-match preference toggles without affecting scoring rules chosen at start.
    public func syncActiveMatchPreferences(
        usThemLabels: Bool,
        fixedServerPositions: Bool,
        askServeAtSetStart: Bool
    ) {
        guard var match = activeMatch, match.status == .inProgress else { return }
        match.settings.usThemLabels = usThemLabels
        match.settings.fixedServerPositions = fixedServerPositions
        match.settings.askServeAtSetStart = askServeAtSetStart
        activeMatch = match
        persist()
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
            archivedMatches = visibleArchive((try? store.loadArchivedMatches()) ?? archivedMatches)
        }
        activeMatch = nil
        try? store.saveActiveMatch(nil)
        notifySync()
    }

    /// Removes a match from history for good. The tombstone survives so a later Watch
    /// snapshot cannot resurrect it. The in-progress match is owned by the Watch and is
    /// never deleted here.
    public func deleteArchivedMatch(id: UUID) {
        guard id != activeMatch?.id else {
            logger.info("Refused to delete the active match \(id.uuidString)")
            return
        }
        deletedMatchIDs.insert(id)
        try? store.saveDeletedMatchIDs(deletedMatchIDs)
        try? store.deleteArchivedMatch(id: id)
        archivedMatches.removeAll { $0.id == id }
        if matchNotes.removeValue(forKey: id) != nil {
            try? store.saveMatchNotes(matchNotes)
        }
        notifySync()
        logger.info("Deleted archived match \(id.uuidString)")
    }

    /// Free text the user attached to a match on the phone. Notes live outside the
    /// synced `MatchState`, so they survive the Watch replacing the archive wholesale.
    public func note(for id: UUID) -> String {
        matchNotes[id] ?? ""
    }

    public func setNote(_ text: String, for id: UUID) {
        // A detail view saves its draft as it disappears, which includes being dismissed
        // by a delete — that must not resurrect the note it just pruned.
        guard !deletedMatchIDs.contains(id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = matchNotes[id]
        if trimmed.isEmpty {
            guard existing != nil else { return }
            matchNotes.removeValue(forKey: id)
        } else {
            guard existing != trimmed else { return }
            matchNotes[id] = trimmed
        }
        do {
            try store.saveMatchNotes(matchNotes)
        } catch {
            logger.error("Saving note failed: \(error.localizedDescription)")
        }
    }

    /// Used by the phone when receiving Watch sync payloads.
    public func applyRemoteSnapshot(active: MatchState?, archive: [MatchState]) {
        activeMatch = active
        archivedMatches = visibleArchive(archive)
        try? store.saveActiveMatch(active)
        try? store.replaceArchive(archivedMatches)
    }

    /// Used by the Watch when the phone reports matches the user deleted from history.
    /// Archive only — the active match is never touched by a remote payload.
    public func applyRemoteDeletions(_ ids: Set<UUID>) {
        let incoming = Set(ids.filter { $0 != activeMatch?.id })
        guard !incoming.isEmpty else { return }
        deletedMatchIDs.formUnion(incoming)
        try? store.saveDeletedMatchIDs(deletedMatchIDs)
        let doomed = archivedMatches.filter { incoming.contains($0.id) }
        for match in doomed {
            try? store.deleteArchivedMatch(id: match.id)
        }
        archivedMatches.removeAll { incoming.contains($0.id) }
        logger.info("Applied \(incoming.count) remote deletion(s)")
    }

    private func visibleArchive(_ matches: [MatchState]) -> [MatchState] {
        matches
            .filter { $0.status != .discarded && !deletedMatchIDs.contains($0.id) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func finalizeActiveMatch() {
        guard let match = activeMatch else { return }
        if match.status != .discarded {
            try? store.archiveMatch(match)
            archivedMatches = visibleArchive((try? store.loadArchivedMatches()) ?? [])
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
        syncHandler?(activeMatch, archivedMatches, deletedMatchIDs)
    }
}
