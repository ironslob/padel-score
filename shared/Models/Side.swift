import Foundation

/// Court orientation: serving side left, receiving side right (product convention).
public enum Side: String, Codable, Sendable, CaseIterable, Equatable {
    case left
    case right

    public var opposite: Side {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }

    public var displayName: String {
        switch self {
        case .left: return "Us"
        case .right: return "Them"
        }
    }
}
