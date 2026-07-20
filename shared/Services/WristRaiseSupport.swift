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

public protocol ServeSelectionPreferenceStoring {
    var alwaysAskServeAtSetStart: Bool { get }
    func setAlwaysAskServeAtSetStart(_ value: Bool)
    var fixedServerPositions: Bool { get }
    func setFixedServerPositions(_ value: Bool)
    var usThemLabels: Bool { get }
    func setUsThemLabels(_ value: Bool)
    var goldenPointEnabled: Bool { get }
    func setGoldenPointEnabled(_ value: Bool)
    var matchSetFormat: MatchSetFormat { get }
    func setMatchSetFormat(_ value: MatchSetFormat)
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

public struct UserDefaultsServeSelectionPreferenceStore: ServeSelectionPreferenceStoring {
    private let askServeKey = "alwaysAskServeAtSetStart"
    private let fixedServerKey = "fixedServerPositions"
    private let usThemLabelsKey = "usThemLabels"
    private let goldenPointKey = "goldenPointEnabled"
    private let matchSetFormatKey = "matchSetFormat"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            goldenPointKey: true,
            usThemLabelsKey: true,
            fixedServerKey: true,
            matchSetFormatKey: MatchSetFormat.bestOfThree.rawValue,
        ])
    }

    public var alwaysAskServeAtSetStart: Bool {
        defaults.bool(forKey: askServeKey)
    }

    public func setAlwaysAskServeAtSetStart(_ value: Bool) {
        defaults.set(value, forKey: askServeKey)
    }

    public var fixedServerPositions: Bool {
        defaults.bool(forKey: fixedServerKey)
    }

    public func setFixedServerPositions(_ value: Bool) {
        defaults.set(value, forKey: fixedServerKey)
    }

    public var usThemLabels: Bool {
        defaults.bool(forKey: usThemLabelsKey)
    }

    public func setUsThemLabels(_ value: Bool) {
        defaults.set(value, forKey: usThemLabelsKey)
    }

    public var goldenPointEnabled: Bool {
        defaults.bool(forKey: goldenPointKey)
    }

    public func setGoldenPointEnabled(_ value: Bool) {
        defaults.set(value, forKey: goldenPointKey)
    }

    public var matchSetFormat: MatchSetFormat {
        guard let raw = defaults.string(forKey: matchSetFormatKey),
              let format = MatchSetFormat(rawValue: raw) else {
            return .bestOfThree
        }
        return format
    }

    public func setMatchSetFormat(_ value: MatchSetFormat) {
        defaults.set(value.rawValue, forKey: matchSetFormatKey)
    }
}

public enum SettingsCopy {
    public static let goldenPoint =
        "After advantage is lost at deuce, the next point wins the game."

    public static let usThemLabels =
        "Score buttons show Us and Them instead of Serving and Receiving."

    public static let fixedServerPositions =
        "After each game, Us and Them swap so the serving team stays on the left."

    public static let askServeAtSetStart =
        "Choose who serves when each new set begins."

    public static let matchSetFormat =
        "How many sets decide the match. Continuous keeps scoring until you finish."
}

public enum DuringPlayAccessCopy {
    public static let firstMatchTip =
        "Pin Padel Score in your Dock, then swipe up from the watch face to reopen. " +
        "Add the Match Glance widget to your Smart Stack for score and elapsed time between points."

    public static let scoreOnlyConsequence =
        "Scores the match without starting a Health workout."

    public static let trackAsWorkoutConsequence =
        "Padel Score owns the workout and usually returns on wrist raise. Only one workout can run at a time."

    public static let helpTitle = "During play"

    public static let helpSections: [(title: String, body: String)] = [
        (
            "Smart Stack",
            "Turn the Digital Crown up or swipe up from the watch face, tap +, and add Padel Score → Match Glance. " +
            "Pin it to keep score and elapsed time at the top. When tracking as a workout, Apple's workout timer " +
            "appears separately; Match Glance shows your score."
        ),
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
