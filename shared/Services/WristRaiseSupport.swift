import Foundation

public enum WorkoutSessionError: Error, Equatable {
    case healthDataUnavailable
    case authorizationDenied
    case anotherWorkoutSessionActive
    case notRunning

    public var userMessage: String {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .authorizationDenied:
            return "Health permission is required to track workouts."
        case .anotherWorkoutSessionActive:
            return "Another workout is already running. Use Score only, or end the other workout first."
        case .notRunning:
            return "No workout session is active."
        }
    }
}

public protocol WristRaiseTipStoring {
    var shouldShowTip: Bool { get }
    func markTipSeen()
}

public protocol WorkoutModePreferenceStoring {
    var preferredWorkoutTrackingModeRawValue: String? { get }
    func setPreferredWorkoutTrackingModeRawValue(_ rawValue: String)
}

public struct UserDefaultsWristRaiseTipStore: WristRaiseTipStoring {
    private let key = "hasSeenWristRaiseTip"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var shouldShowTip: Bool {
        !defaults.bool(forKey: key)
    }

    public func markTipSeen() {
        defaults.set(true, forKey: key)
    }
}

public struct UserDefaultsWorkoutModePreferenceStore: WorkoutModePreferenceStoring {
    private let key = "preferredWorkoutTrackingMode"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var preferredWorkoutTrackingModeRawValue: String? {
        defaults.string(forKey: key)
    }

    public func setPreferredWorkoutTrackingModeRawValue(_ rawValue: String) {
        defaults.set(rawValue, forKey: key)
    }
}

public enum DuringPlayAccessCopy {
    public static let firstMatchTip =
        "Score only works best when another workout app is active. " +
        "Pin Padel Score in your Dock, then swipe up from the watch face to reopen. " +
        "Between points, check the dimmed score on your wrist."

    public static let scoreOnlyConsequence =
        "Best with Bevel or another workout app. Wrist raise may return to that app first."

    public static let trackAsWorkoutConsequence =
        "Padel Score owns the workout and usually returns on wrist raise. Only one workout can run at a time."

    public static let helpTitle = "During play"

    public static let helpSections: [(title: String, body: String)] = [
        (
            "Swipe up",
            "Swipe up from the watch face to open the Dock, then tap Padel Score. " +
            "Pin the app in the Dock on your iPhone’s Watch app for one-tap access."
        ),
        (
            "Glance at your wrist",
            "Between points, the dimmed always-on screen shows the current score without opening the app."
        ),
        (
            "Watch face",
            "Add the Padel Score complication to see the score on your watch face."
        )
    ]
}
