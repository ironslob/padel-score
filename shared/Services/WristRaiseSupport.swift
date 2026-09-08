import Foundation

public enum WorkoutSessionError: Error, Equatable {
    case healthDataUnavailable
    case authorizationDenied
    case anotherWorkoutSessionActive
    case notRunning

    public var userMessage: String {
        switch self {
        case .healthDataUnavailable:
            return WorkoutConflictCopy.healthUnavailableMessage
        case .authorizationDenied:
            return WorkoutConflictCopy.authorizationDeniedMessage
        case .anotherWorkoutSessionActive:
            return WorkoutConflictCopy.message
        case .notRunning:
            return "No workout session is active."
        }
    }
}

public protocol WristRaiseTipStoring {
    var shouldShowTip: Bool { get }
    func markTipSeen()
}

public protocol ServeSelectionPreferenceStoring {
    var alwaysAskServeAtSetStart: Bool { get }
    func setAlwaysAskServeAtSetStart(_ value: Bool)
    var fixedServerPositions: Bool { get }
    func setFixedServerPositions(_ value: Bool)
    var usThemLabels: Bool { get }
    func setUsThemLabels(_ value: Bool)
    var deuceFormat: DeuceFormat { get }
    func setDeuceFormat(_ value: DeuceFormat)
    var matchSetFormat: MatchSetFormat { get }
    func setMatchSetFormat(_ value: MatchSetFormat)
    var warmUpEnabled: Bool { get }
    func setWarmUpEnabled(_ value: Bool)
    var warmUpMinutes: Int { get }
    func setWarmUpMinutes(_ value: Int)
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

public struct UserDefaultsServeSelectionPreferenceStore: ServeSelectionPreferenceStoring {
    private let askServeKey = "alwaysAskServeAtSetStart"
    private let fixedServerKey = "fixedServerPositions"
    private let usThemLabelsKey = "usThemLabels"
    private let legacyGoldenPointKey = "goldenPointEnabled"
    private let deuceFormatKey = "deuceFormat"
    private let matchSetFormatKey = "matchSetFormat"
    private let warmUpEnabledKey = "warmUpEnabled"
    private let warmUpMinutesKey = "warmUpMinutes"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `deuceFormat` is deliberately not registered — its getter needs to see the
        // key genuinely absent to migrate from the old `goldenPointEnabled` toggle.
        defaults.register(defaults: [
            usThemLabelsKey: true,
            fixedServerKey: true,
            matchSetFormatKey: MatchSetFormat.bestOfThree.rawValue,
            warmUpEnabledKey: true,
            warmUpMinutesKey: MatchSettings.defaultWarmUpMinutes,
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

    public var deuceFormat: DeuceFormat {
        if let raw = defaults.string(forKey: deuceFormatKey),
           let format = DeuceFormat(rawValue: raw) {
            return format
        }
        // Upgrading from the two-way toggle: someone who turned it off wanted
        // full advantage scoring, so honour that. Everyone else (and fresh
        // installs) gets the product default.
        if defaults.object(forKey: legacyGoldenPointKey) as? Bool == false {
            return .advantage
        }
        return MatchSettings.default.deuceFormat
    }

    public func setDeuceFormat(_ value: DeuceFormat) {
        defaults.set(value.rawValue, forKey: deuceFormatKey)
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

    public var warmUpEnabled: Bool {
        defaults.bool(forKey: warmUpEnabledKey)
    }

    public func setWarmUpEnabled(_ value: Bool) {
        defaults.set(value, forKey: warmUpEnabledKey)
    }

    public var warmUpMinutes: Int {
        MatchSettings.clampedWarmUpMinutes(defaults.integer(forKey: warmUpMinutesKey))
    }

    public func setWarmUpMinutes(_ value: Int) {
        defaults.set(MatchSettings.clampedWarmUpMinutes(value), forKey: warmUpMinutesKey)
    }
}

public enum SettingsCopy {
    public static let deuceFormat =
        "How a game is decided at 40-40. Regular plays advantage until someone wins by two. " +
        "Star point plays two advantages, then the next point wins. " +
        "Silver point plays one advantage, then the next point wins. " +
        "Golden point skips advantage entirely — the next point wins. " +
        "Can be changed during a match; games already played keep their result."

    public static let usThemLabels =
        "Score buttons show Us and Them instead of Serving and Receiving."

    public static let fixedServerPositions =
        "After each game, Us and Them swap so the serving team stays on the left. Serve still alternates when this is off."

    public static let askServeAtSetStart =
        "Always choose who serves when each new set begins. With this off, the set " +
        "summary still offers New serve when you want to change it."

    public static let matchSetFormat =
        "How many sets decide the match. 2 sets + TB replaces the third set with a 10-point tie-break. Continuous keeps scoring until you finish."

    public static let warmUp =
        "A timer before you pick who serves. Only at match start. Tap Play when ready."

    public static let warmUpLimit =
        "No limit runs until Play. 3, 5, or 10 minutes auto-advances."
}

public enum FirstLaunchTipCopy {
    public static let title = "Before you start"

    public static let tipSections: [(title: String, body: String)] = [
        (
            "Health",
            "Wrist Rally needs Health access to track the match as a workout so it can return when you raise your wrist."
        ),
        (
            "Settings",
            "Match length, scoring at deuce, labels, and serve options are in Settings on the home screen—set them before you start a match."
        ),
    ]
}

public enum WorkoutConflictCopy {
    public static let title = "Can't track as a workout"

    public static let continueWithoutWorkout = "Track without workout"

    public static let cancelMatchStart = "Cancel match start"

    public static let message =
        "Another app is already tracking, and Apple Watch only allows one workout at a time. " +
        "Without a workout, Wrist Rally usually won't return when you raise your wrist."

    public static let genericFailureMessage =
        "Could not start a Health workout. Scoring continues, but the app usually won't return when you raise your wrist."

    public static let healthUnavailableMessage =
        "Health data is not available on this device. Scoring continues, but the app usually won't return when you raise your wrist."

    public static let authorizationDeniedMessage =
        "Health permission is required to track a workout. Scoring continues, but the app usually won't return when you raise your wrist."
}

public enum DuringPlayAccessCopy {
    public static let helpTitle = "During play"

    public static let helpSections: [(title: String, body: String)] = [
        (
            "Smart Stack",
            "Turn the Digital Crown up or swipe up from the watch face, tap +, and add Wrist Rally → Match Glance. " +
            "Pin it to keep score and elapsed time at the top. When tracking as a workout, Apple's workout timer " +
            "appears separately; Match Glance shows your score."
        ),
        (
            "Swipe up",
            "Swipe up from the watch face to open the Dock, then tap Wrist Rally. " +
            "Pin the app in the Dock on your iPhone’s Watch app for one-tap access."
        ),
        (
            "Glance at your wrist",
            "Between points, the dimmed always-on screen shows the current score without opening the app."
        ),
        (
            "Watch face",
            "Add the Wrist Rally complication to see the score on your watch face."
        )
    ]
}
