import Foundation

public enum MatchStatus: String, Codable, Sendable, Equatable {
    case inProgress
    case completed
    case endedEarly
    case discarded

    public var isTerminal: Bool {
        switch self {
        case .inProgress:
            return false
        case .completed, .endedEarly, .discarded:
            return true
        }
    }

    public var displayName: String {
        switch self {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .endedEarly: return "Ended Early"
        case .discarded: return "Discarded"
        }
    }
}
