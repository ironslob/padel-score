import Foundation

/// Logical team side: left = Us, right = Them. Visual layout may remap when swap-sides is on.
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
