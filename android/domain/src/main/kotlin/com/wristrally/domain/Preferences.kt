package com.wristrally.domain

sealed class WorkoutSessionError : Exception() {
    data object HealthDataUnavailable : WorkoutSessionError()
    data object AuthorizationDenied : WorkoutSessionError()
    data object AnotherWorkoutSessionActive : WorkoutSessionError()
    data object NotRunning : WorkoutSessionError()

    val userMessage: String
        get() = when (this) {
            HealthDataUnavailable -> WorkoutConflictCopy.healthUnavailableMessage
            AuthorizationDenied -> WorkoutConflictCopy.authorizationDeniedMessage
            AnotherWorkoutSessionActive -> WorkoutConflictCopy.message
            NotRunning -> "No workout session is active."
        }
}

interface WristRaiseTipStoring {
    val shouldShowTip: Boolean
    fun markTipSeen()
}

interface ServeSelectionPreferenceStoring {
    var alwaysAskServeAtSetStart: Boolean
    var fixedServerPositions: Boolean
    var usThemLabels: Boolean
    var deuceFormat: DeuceFormat
    var matchSetFormat: MatchSetFormat
    var warmUpEnabled: Boolean
    var warmUpMinutes: Int
}

class InMemoryTipStore : WristRaiseTipStoring {
    private var seen = false
    override val shouldShowTip: Boolean get() = !seen
    override fun markTipSeen() { seen = true }
}

class InMemoryPreferenceStore : ServeSelectionPreferenceStoring {
    override var alwaysAskServeAtSetStart: Boolean = false
    override var fixedServerPositions: Boolean = true
    override var usThemLabels: Boolean = true
    override var deuceFormat: DeuceFormat = DeuceFormat.StarPoint
    override var matchSetFormat: MatchSetFormat = MatchSetFormat.BestOfThree
    override var warmUpEnabled: Boolean = true
    override var warmUpMinutes: Int = MatchSettings.DEFAULT_WARM_UP_MINUTES
}

object SettingsCopy {
    const val deuceFormat =
        "How a game is decided at 40-40. Regular plays advantage until someone wins by two. " +
            "Star point plays two advantages, then the next point wins. " +
            "Silver point plays one advantage, then the next point wins. " +
            "Golden point skips advantage entirely — the next point wins. " +
            "Can be changed during a match; games already played keep their result."

    const val usThemLabels =
        "Score buttons show Us and Them instead of Serving and Receiving."

    const val fixedServerPositions =
        "After each game, Us and Them swap so the serving team stays on the left. Serve still alternates when this is off."

    const val askServeAtSetStart =
        "Always choose who serves when each new set begins. With this off, the set " +
            "summary still offers New serve when you want to change it."

    const val matchSetFormat =
        "How many sets decide the match. 2 sets + TB replaces the third set with a 10-point tie-break. Continuous keeps scoring until you finish."

    const val warmUp =
        "A timer before you pick who serves. Only at match start. Tap Play when ready."

    const val warmUpLimit =
        "No limit runs until Play. 3, 5, or 10 minutes auto-advances."
}

object FirstLaunchTipCopy {
    const val title = "Before you start"

    val tipSections: List<Pair<String, String>> = listOf(
        "Health" to
            "Wrist Rally needs activity permission to track the match as a workout so it can return when you raise your wrist.",
        "Settings" to
            "Match length, scoring at deuce, labels, and serve options are in Settings on the home screen—set them before you start a match.",
    )
}

object WorkoutConflictCopy {
    const val title = "Can't track as a workout"
    const val continueWithoutWorkout = "Track without workout"
    const val cancelMatchStart = "Cancel match start"
    const val message =
        "Another app is already tracking, and Wear OS only allows one workout at a time. " +
            "Without a workout, Wrist Rally usually won't return when you raise your wrist."
    const val genericFailureMessage =
        "Could not start a workout. Scoring continues, but the app usually won't return when you raise your wrist."
    const val healthUnavailableMessage =
        "Health data is not available on this device. Scoring continues, but the app usually won't return when you raise your wrist."
    const val authorizationDeniedMessage =
        "Activity permission is required to track a workout. Scoring continues, but the app usually won't return when you raise your wrist."
}

object DuringPlayAccessCopy {
    const val helpTitle = "During play"

    val helpSections: List<Pair<String, String>> = listOf(
        "Recents" to
            "Swipe up from the watch face to open recent apps, then tap Wrist Rally. " +
            "Keep the app in recents so you can return between points.",
        "Glance at your wrist" to
            "Between points, the dimmed always-on screen shows the current score without opening the app.",
        "Raise your wrist" to
            "When tracking as a workout, raising your wrist returns you to the score screen.",
    )
}

object WorkoutPauseResumeLogic {
    enum class Action { Pause, Resume }

    fun action(isPaused: Boolean): Action = if (isPaused) Action.Resume else Action.Pause
}
