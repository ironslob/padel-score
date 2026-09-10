package com.wristrally.phone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.wristrally.domain.MatchState
import com.wristrally.domain.MatchStatus

/** Ongoing notification analog of the iPhone Live Activity. */
class MatchLiveNotificationManager(private val context: Context) {
    init {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live match",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Score of the match in progress on your watch"
                setShowBadge(false)
            }
            NotificationManagerCompat.from(context).createNotificationChannel(channel)
        }
    }

    fun sync(match: MatchState?) {
        if (match == null || match.status == MatchStatus.Discarded) {
            cancel()
            return
        }
        notify(match)
    }

    private fun notify(match: MatchState) {
        val game = match.gameDisplayPair
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_MATCH_ID, match.id.toString())
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val ongoing = match.status == MatchStatus.InProgress
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Wrist Rally")
            .setContentText("${game.first}–${game.second}  ·  Set ${match.currentSet.leftGames}–${match.currentSet.rightGames}")
            .setContentIntent(pending)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
        runCatching {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        }
    }

    private fun cancel() {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    companion object {
        private const val CHANNEL_ID = "wristrally_live_match"
        private const val NOTIFICATION_ID = 41
    }
}
