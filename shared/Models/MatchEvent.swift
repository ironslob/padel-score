import Foundation

public enum MatchEventKind: String, Codable, Sendable, Equatable {
    case matchStarted
    case serverSelected
    case pointWon
    case matchFinished
    case matchEndedEarly
    case matchDiscarded
}

/// Immutable fact in the match event stream.
public struct MatchEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: MatchEventKind
    public let side: Side?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        kind: MatchEventKind,
        side: Side? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.side = side
        self.timestamp = timestamp
    }

    public static func matchStarted(at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .matchStarted, timestamp: date)
    }

    public static func pointWon(_ side: Side, at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .pointWon, side: side, timestamp: date)
    }

    public static func serverSelected(_ side: Side, at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .serverSelected, side: side, timestamp: date)
    }

    public static func matchFinished(at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .matchFinished, timestamp: date)
    }

    public static func matchEndedEarly(at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .matchEndedEarly, timestamp: date)
    }

    public static func matchDiscarded(at date: Date = Date()) -> MatchEvent {
        MatchEvent(kind: .matchDiscarded, timestamp: date)
    }
}
