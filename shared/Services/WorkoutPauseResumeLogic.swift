import Foundation

public enum WorkoutPauseResumeLogic {
    public enum Action: Equatable {
        case pause
        case resume
    }

    public static func action(isPaused: Bool) -> Action {
        isPaused ? .resume : .pause
    }
}
