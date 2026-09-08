package com.wristrally.wear

import android.content.Context
import android.content.SharedPreferences
import com.wristrally.domain.DeuceFormat
import com.wristrally.domain.MatchSettings
import com.wristrally.domain.MatchSetFormat
import com.wristrally.domain.ServeSelectionPreferenceStoring
import com.wristrally.domain.WristRaiseTipStoring

class SharedPreferencesTipStore(
    private val prefs: SharedPreferences,
) : WristRaiseTipStoring {
    override val shouldShowTip: Boolean
        get() = !prefs.getBoolean(KEY, false)

    override fun markTipSeen() {
        prefs.edit().putBoolean(KEY, true).apply()
    }

    companion object {
        private const val KEY = "hasSeenWristRaiseTip"
        fun create(context: Context) =
            SharedPreferencesTipStore(context.getSharedPreferences("wristrally", Context.MODE_PRIVATE))
    }
}

class SharedPreferencesStore(
    private val prefs: SharedPreferences,
) : ServeSelectionPreferenceStoring {
    init {
        prefs.edit().apply {
            if (!prefs.contains(US_THEM)) putBoolean(US_THEM, true)
            if (!prefs.contains(FIXED_SERVER)) putBoolean(FIXED_SERVER, true)
            if (!prefs.contains(MATCH_FORMAT)) putString(MATCH_FORMAT, MatchSetFormat.BestOfThree.rawValue)
            if (!prefs.contains(WARM_UP_ENABLED)) putBoolean(WARM_UP_ENABLED, true)
            if (!prefs.contains(WARM_UP_MINUTES)) putInt(WARM_UP_MINUTES, MatchSettings.DEFAULT_WARM_UP_MINUTES)
            apply()
        }
    }

    override var alwaysAskServeAtSetStart: Boolean
        get() = prefs.getBoolean(ASK_SERVE, false)
        set(value) { prefs.edit().putBoolean(ASK_SERVE, value).apply() }

    override var fixedServerPositions: Boolean
        get() = prefs.getBoolean(FIXED_SERVER, true)
        set(value) { prefs.edit().putBoolean(FIXED_SERVER, value).apply() }

    override var usThemLabels: Boolean
        get() = prefs.getBoolean(US_THEM, true)
        set(value) { prefs.edit().putBoolean(US_THEM, value).apply() }

    override var deuceFormat: DeuceFormat
        get() {
            val raw = prefs.getString(DEUCE, null)
            DeuceFormat.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) || serialName(it) == raw }?.let { return it }
            if (prefs.contains(LEGACY_GOLDEN) && !prefs.getBoolean(LEGACY_GOLDEN, true)) {
                return DeuceFormat.Advantage
            }
            return MatchSettings().deuceFormat
        }
        set(value) { prefs.edit().putString(DEUCE, serialName(value)).apply() }

    override var matchSetFormat: MatchSetFormat
        get() = MatchSetFormat.fromRaw(prefs.getString(MATCH_FORMAT, null))
        set(value) { prefs.edit().putString(MATCH_FORMAT, value.rawValue).apply() }

    override var warmUpEnabled: Boolean
        get() = prefs.getBoolean(WARM_UP_ENABLED, true)
        set(value) { prefs.edit().putBoolean(WARM_UP_ENABLED, value).apply() }

    override var warmUpMinutes: Int
        get() = MatchSettings.clampedWarmUpMinutes(prefs.getInt(WARM_UP_MINUTES, MatchSettings.DEFAULT_WARM_UP_MINUTES))
        set(value) { prefs.edit().putInt(WARM_UP_MINUTES, MatchSettings.clampedWarmUpMinutes(value)).apply() }

    companion object {
        private const val ASK_SERVE = "alwaysAskServeAtSetStart"
        private const val FIXED_SERVER = "fixedServerPositions"
        private const val US_THEM = "usThemLabels"
        private const val LEGACY_GOLDEN = "goldenPointEnabled"
        private const val DEUCE = "deuceFormat"
        private const val MATCH_FORMAT = "matchSetFormat"
        private const val WARM_UP_ENABLED = "warmUpEnabled"
        private const val WARM_UP_MINUTES = "warmUpMinutes"

        fun create(context: Context) =
            SharedPreferencesStore(context.getSharedPreferences("wristrally", Context.MODE_PRIVATE))

        private fun serialName(format: DeuceFormat): String = when (format) {
            DeuceFormat.Advantage -> "advantage"
            DeuceFormat.StarPoint -> "starPoint"
            DeuceFormat.SilverPoint -> "silverPoint"
            DeuceFormat.GoldenPoint -> "goldenPoint"
        }
    }
}
