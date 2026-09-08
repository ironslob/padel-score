package com.wristrally.domain

import java.time.Instant
import java.util.UUID
import java.util.logging.Logger

/** Coordinates scoring engine + persistence. Owns the single active match workflow. */
class MatchService(
    private val store: MatchStore,
    private val engine: ScoringEngine = ScoringEngine(),
    autoRestore: Boolean = true,
) {
    private val logger = Logger.getLogger("com.wristrally.MatchService")
    private val listeners = mutableListOf<() -> Unit>()

    var activeMatch: MatchState? = null
        private set(value) {
            field = value
            notifyListeners()
        }
    var archivedMatches: List<MatchState> = emptyList()
        private set
    var deletedMatchIDs: Set<UUID> = emptySet()
        private set
    var matchNotes: Map<UUID, String> = emptyMap()
        private set
    var isRestored: Boolean = false
        private set

    private var syncHandler: ((MatchState?, List<MatchState>, Set<UUID>) -> Unit)? = null

    init {
        if (autoRestore) restore()
    }

    fun addListener(listener: () -> Unit) {
        listeners += listener
    }

    fun removeListener(listener: () -> Unit) {
        listeners -= listener
    }

    fun onSyncNeeded(handler: (MatchState?, List<MatchState>, Set<UUID>) -> Unit) {
        syncHandler = handler
    }

    fun restore() {
        try {
            deletedMatchIDs = store.loadDeletedMatchIDs()
            matchNotes = store.loadMatchNotes()
            activeMatch = store.loadActiveMatch()?.let { engine.rehydrate(it) }
            archivedMatches = visibleArchive(store.loadArchivedMatches().map { engine.rehydrate(it) })
            logger.info("Restored active=${activeMatch != null} archive=${archivedMatches.size}")
            finishRestore()
        } catch (error: Exception) {
            logger.warning("Restore failed: ${error.message}")
            activeMatch = null
            archivedMatches = emptyList()
            isRestored = true
        }
    }

    private fun finishRestore() {
        isRestored = true
        expireInactiveMatchIfNeeded()
    }

    fun startMatch(settings: MatchSettings = MatchSettings()) {
        if (activeMatch != null) return
        val match = engine.startMatch(settings)
        activeMatch = match
        persist()
        logger.info("Match started ${match.id}")
    }

    fun awardPoint(to: Side) {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.PointWon(to), match)
            activeMatch = match
            if (match.status == MatchStatus.Completed) {
                finalizeActiveMatch()
            } else {
                persist()
                expireInactiveMatchIfNeeded()
            }
        } catch (error: Exception) {
            logger.warning("Point failed: ${error.message}")
        }
    }

    fun selectServer(side: Side) {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.SelectServer(side), match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
        } catch (error: Exception) {
            logger.warning("Select server failed: ${error.message}")
        }
    }

    fun requestServerSelection() {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.RequestServerSelection, match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
        } catch (error: Exception) {
            logger.warning("Server selection request failed: ${error.message}")
        }
    }

    fun completeWarmUp() {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.CompleteWarmUp, match)
            activeMatch = match
            persist()
        } catch (error: Exception) {
            logger.warning("Complete warm-up failed: ${error.message}")
        }
    }

    fun undoLastPoint() {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.Undo, match)
            activeMatch = match
            persist()
            expireInactiveMatchIfNeeded()
        } catch (error: Exception) {
            logger.warning("Undo failed: ${error.message}")
        }
    }

    val canUndo: Boolean
        get() {
            val match = activeMatch ?: return false
            if (match.status != MatchStatus.InProgress) return false
            return match.events.any { it.kind == MatchEventKind.PointWon }
        }

    fun setDeuceFormat(format: DeuceFormat) {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        if (match.settings.deuceFormat == format) return
        try {
            match = engine.apply(MatchAction.SetDeuceFormat(format), match)
            activeMatch = match
            persist()
        } catch (error: Exception) {
            logger.warning("Deuce format change failed: ${error.message}")
        }
    }

    fun syncActiveMatchPreferences(
        usThemLabels: Boolean,
        fixedServerPositions: Boolean,
        askServeAtSetStart: Boolean,
    ) {
        val match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        val updated = match.deepCopy()
        updated.settings = updated.settings.copy(
            usThemLabels = usThemLabels,
            fixedServerPositions = fixedServerPositions,
            askServeAtSetStart = askServeAtSetStart,
        )
        activeMatch = updated
        persist()
    }

    fun finishMatch() {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.Finish, match)
            activeMatch = match
            finalizeActiveMatch()
        } catch (error: Exception) {
            logger.warning("Finish failed: ${error.message}")
        }
    }

    fun expireInactiveMatchIfNeeded(at: Instant = Instant.now()) {
        val match = activeMatch ?: return
        if (!match.isInactive(at)) return
        if (match.hasScoredPoints) {
            endMatchEarly()
        } else {
            discardMatch()
        }
    }

    fun endMatchEarly() {
        var match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            match = engine.apply(MatchAction.EndEarly, match)
            activeMatch = match
            finalizeActiveMatch()
        } catch (error: Exception) {
            logger.warning("End early failed: ${error.message}")
        }
    }

    fun discardMatch() {
        val match = activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        try {
            engine.apply(MatchAction.Discard, match)
            activeMatch = null
            store.saveActiveMatch(null)
            notifySync()
        } catch (error: Exception) {
            logger.warning("Discard failed: ${error.message}")
        }
    }

    fun acknowledgeCompletedMatch() {
        val match = activeMatch
        if (match == null || !match.status.isTerminal || match.status == MatchStatus.Discarded) {
            activeMatch = null
            runCatching { store.saveActiveMatch(null) }
            notifySync()
            return
        }
        if (archivedMatches.none { it.id == match.id }) {
            runCatching { store.archiveMatch(match) }
            archivedMatches = visibleArchive(
                runCatching { store.loadArchivedMatches() }.getOrDefault(archivedMatches),
            )
        }
        activeMatch = null
        runCatching { store.saveActiveMatch(null) }
        notifySync()
    }

    fun deleteArchivedMatch(id: UUID) {
        if (id == activeMatch?.id) return
        deletedMatchIDs = deletedMatchIDs + id
        runCatching { store.saveDeletedMatchIDs(deletedMatchIDs) }
        runCatching { store.deleteArchivedMatch(id) }
        archivedMatches = archivedMatches.filterNot { it.id == id }
        if (matchNotes.containsKey(id)) {
            matchNotes = matchNotes - id
            runCatching { store.saveMatchNotes(matchNotes) }
        }
        notifySync()
    }

    fun note(id: UUID): String = matchNotes[id].orEmpty()

    fun setNote(text: String, id: UUID) {
        if (deletedMatchIDs.contains(id)) return
        val trimmed = text.trim()
        val existing = matchNotes[id]
        val next = matchNotes.toMutableMap()
        if (trimmed.isEmpty()) {
            if (existing == null) return
            next.remove(id)
        } else {
            if (existing == trimmed) return
            next[id] = trimmed
        }
        matchNotes = next
        runCatching { store.saveMatchNotes(next) }
    }

    fun applyRemoteSnapshot(active: MatchState?, archive: List<MatchState>) {
        activeMatch = active
        archivedMatches = visibleArchive(archive)
        runCatching { store.saveActiveMatch(active) }
        runCatching { store.replaceArchive(archivedMatches) }
    }

    fun applyRemoteDeletions(ids: Set<UUID>) {
        val incoming = ids.filter { it != activeMatch?.id }.toSet()
        if (incoming.isEmpty()) return
        deletedMatchIDs = deletedMatchIDs + incoming
        runCatching { store.saveDeletedMatchIDs(deletedMatchIDs) }
        val doomed = archivedMatches.filter { incoming.contains(it.id) }
        for (match in doomed) {
            runCatching { store.deleteArchivedMatch(match.id) }
        }
        archivedMatches = archivedMatches.filterNot { incoming.contains(it.id) }
    }

    private fun visibleArchive(matches: List<MatchState>): List<MatchState> =
        matches
            .filter { it.status != MatchStatus.Discarded && !deletedMatchIDs.contains(it.id) }
            .sortedByDescending { it.startedAt }

    private fun finalizeActiveMatch() {
        val match = activeMatch ?: return
        if (match.status != MatchStatus.Discarded) {
            runCatching { store.archiveMatch(match) }
            archivedMatches = visibleArchive(
                runCatching { store.loadArchivedMatches() }.getOrDefault(emptyList()),
            )
        }
        runCatching { store.saveActiveMatch(match) }
        notifySync()
    }

    private fun persist() {
        try {
            store.saveActiveMatch(activeMatch)
            notifySync()
        } catch (error: Exception) {
            logger.warning("Persist failed: ${error.message}")
        }
    }

    private fun notifySync() {
        syncHandler?.invoke(activeMatch, archivedMatches, deletedMatchIDs)
    }

    private fun notifyListeners() {
        listeners.toList().forEach { it() }
    }
}
