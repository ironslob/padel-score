import Foundation

public protocol MatchStore: AnyObject {
    func loadActiveMatch() throws -> MatchState?
    func saveActiveMatch(_ match: MatchState?) throws
    func loadArchivedMatches() throws -> [MatchState]
    func archiveMatch(_ match: MatchState) throws
    func deleteArchivedMatch(id: UUID) throws
    func replaceArchive(_ matches: [MatchState]) throws
}

/// JSON file-backed store. Active match is a single file; archive is one file of completed/ended matches.
public final class FileMatchStore: MatchStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(
        directory: URL,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public convenience init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PadelScore", isDirectory: true)
        self.init(directory: dir, fileManager: fileManager)
    }

    private var activeURL: URL {
        directory.appendingPathComponent("active-match.json")
    }

    private var archiveURL: URL {
        directory.appendingPathComponent("match-archive.json")
    }

    public func loadActiveMatch() throws -> MatchState? {
        guard fileManager.fileExists(atPath: activeURL.path) else { return nil }
        let data = try Data(contentsOf: activeURL)
        if data.isEmpty { return nil }
        return try decoder.decode(MatchState.self, from: data)
    }

    public func saveActiveMatch(_ match: MatchState?) throws {
        if let match {
            let data = try encoder.encode(match)
            try data.write(to: activeURL, options: [.atomic])
        } else if fileManager.fileExists(atPath: activeURL.path) {
            try fileManager.removeItem(at: activeURL)
        }
    }

    public func loadArchivedMatches() throws -> [MatchState] {
        guard fileManager.fileExists(atPath: archiveURL.path) else { return [] }
        let data = try Data(contentsOf: archiveURL)
        if data.isEmpty { return [] }
        let matches = try decoder.decode([MatchState].self, from: data)
        return matches.sorted { $0.startedAt > $1.startedAt }
    }

    public func archiveMatch(_ match: MatchState) throws {
        var matches = try loadArchivedMatches()
        matches.removeAll { $0.id == match.id }
        matches.insert(match, at: 0)
        try replaceArchive(matches)
    }

    public func deleteArchivedMatch(id: UUID) throws {
        var matches = try loadArchivedMatches()
        matches.removeAll { $0.id == id }
        try replaceArchive(matches)
    }

    public func replaceArchive(_ matches: [MatchState]) throws {
        let data = try encoder.encode(matches)
        try data.write(to: archiveURL, options: [.atomic])
    }
}

/// In-memory store for unit tests.
public final class InMemoryMatchStore: MatchStore {
    public var active: MatchState?
    public var archive: [MatchState] = []

    public init() {}

    public func loadActiveMatch() throws -> MatchState? { active }

    public func saveActiveMatch(_ match: MatchState?) throws { active = match }

    public func loadArchivedMatches() throws -> [MatchState] {
        archive.sorted { $0.startedAt > $1.startedAt }
    }

    public func archiveMatch(_ match: MatchState) throws {
        archive.removeAll { $0.id == match.id }
        archive.insert(match, at: 0)
    }

    public func deleteArchivedMatch(id: UUID) throws {
        archive.removeAll { $0.id == id }
    }

    public func replaceArchive(_ matches: [MatchState]) throws {
        archive = matches
    }
}
