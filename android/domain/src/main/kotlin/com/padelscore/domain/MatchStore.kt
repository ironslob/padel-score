package com.padelscore.domain

import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

interface MatchStore {
    fun loadActiveMatch(): MatchState?
    fun saveActiveMatch(match: MatchState?)
    fun loadArchivedMatches(): List<MatchState>
    fun archiveMatch(match: MatchState)
    fun deleteArchivedMatch(id: UUID)
    fun replaceArchive(matches: List<MatchState>)
    fun loadDeletedMatchIDs(): Set<UUID>
    fun saveDeletedMatchIDs(ids: Set<UUID>)
    fun loadMatchNotes(): Map<UUID, String>
    fun saveMatchNotes(notes: Map<UUID, String>)
}

private val matchJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

class FileMatchStore(private val directory: Path) : MatchStore {
    private val activePath: Path get() = directory.resolve("active-match.json")
    private val archivePath: Path get() = directory.resolve("match-archive.json")
    private val deletedPath: Path get() = directory.resolve("deleted-matches.json")
    private val notesPath: Path get() = directory.resolve("match-notes.json")

    init {
        Files.createDirectories(directory)
    }

    override fun loadActiveMatch(): MatchState? {
        if (!Files.exists(activePath)) return null
        val data = Files.readAllBytes(activePath)
        if (data.isEmpty()) return null
        return matchJson.decodeFromString(MatchState.serializer(), data.decodeToString())
    }

    override fun saveActiveMatch(match: MatchState?) {
        if (match != null) {
            val data = matchJson.encodeToString(MatchState.serializer(), match)
            atomicWrite(activePath, data)
        } else if (Files.exists(activePath)) {
            Files.delete(activePath)
        }
    }

    override fun loadArchivedMatches(): List<MatchState> {
        if (!Files.exists(archivePath)) return emptyList()
        val data = Files.readAllBytes(archivePath)
        if (data.isEmpty()) return emptyList()
        return matchJson.decodeFromString(ListSerializer(MatchState.serializer()), data.decodeToString())
            .sortedByDescending { it.startedAt }
    }

    override fun archiveMatch(match: MatchState) {
        val matches = loadArchivedMatches().toMutableList()
        matches.removeAll { it.id == match.id }
        matches.add(0, match)
        replaceArchive(matches)
    }

    override fun deleteArchivedMatch(id: UUID) {
        replaceArchive(loadArchivedMatches().filterNot { it.id == id })
    }

    override fun replaceArchive(matches: List<MatchState>) {
        val data = matchJson.encodeToString(ListSerializer(MatchState.serializer()), matches)
        atomicWrite(archivePath, data)
    }

    override fun loadDeletedMatchIDs(): Set<UUID> {
        if (!Files.exists(deletedPath)) return emptySet()
        val data = Files.readAllBytes(deletedPath)
        if (data.isEmpty()) return emptySet()
        return matchJson.decodeFromString(
            ListSerializer(UuidSerializer),
            data.decodeToString(),
        ).toSet()
    }

    override fun saveDeletedMatchIDs(ids: Set<UUID>) {
        val sorted = ids.sortedBy { it.toString() }
        val data = matchJson.encodeToString(ListSerializer(UuidSerializer), sorted)
        atomicWrite(deletedPath, data)
    }

    override fun loadMatchNotes(): Map<UUID, String> {
        if (!Files.exists(notesPath)) return emptyMap()
        val data = Files.readAllBytes(notesPath)
        if (data.isEmpty()) return emptyMap()
        val raw = matchJson.decodeFromString(
            MapSerializer(String.serializer(), String.serializer()),
            data.decodeToString(),
        )
        return raw.mapNotNull { (key, value) ->
            runCatching { UUID.fromString(key) to value }.getOrNull()
        }.toMap()
    }

    override fun saveMatchNotes(notes: Map<UUID, String>) {
        val raw = notes.entries.associate { it.key.toString() to it.value }
        val data = matchJson.encodeToString(
            MapSerializer(String.serializer(), String.serializer()),
            raw,
        )
        atomicWrite(notesPath, data)
    }

    private fun atomicWrite(path: Path, data: String) {
        val tmp = path.resolveSibling("${path.fileName}.tmp")
        Files.writeString(tmp, data)
        try {
            Files.move(
                tmp,
                path,
                java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(tmp, path, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        }
    }
}

class InMemoryMatchStore : MatchStore {
    var active: MatchState? = null
    var archive: MutableList<MatchState> = mutableListOf()
    var deletedIDs: MutableSet<UUID> = mutableSetOf()
    var notes: MutableMap<UUID, String> = mutableMapOf()

    override fun loadActiveMatch(): MatchState? = active
    override fun saveActiveMatch(match: MatchState?) { active = match }
    override fun loadArchivedMatches(): List<MatchState> = archive.sortedByDescending { it.startedAt }
    override fun archiveMatch(match: MatchState) {
        archive.removeAll { it.id == match.id }
        archive.add(0, match)
    }
    override fun deleteArchivedMatch(id: UUID) { archive.removeAll { it.id == id } }
    override fun replaceArchive(matches: List<MatchState>) { archive = matches.toMutableList() }
    override fun loadDeletedMatchIDs(): Set<UUID> = deletedIDs.toSet()
    override fun saveDeletedMatchIDs(ids: Set<UUID>) { deletedIDs = ids.toMutableSet() }
    override fun loadMatchNotes(): Map<UUID, String> = notes.toMap()
    override fun saveMatchNotes(notes: Map<UUID, String>) { this.notes = notes.toMutableMap() }
}
