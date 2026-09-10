package com.wristrally.phone

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import java.util.UUID

class MainActivity : ComponentActivity() {
    private val requestNotifications = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* History remains usable if denied. */ }

    private var deepLinkMatchId by mutableStateOf<UUID?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deepLinkMatchId = matchIdFrom(intent)
        maybeRequestNotifications()
        val app = application as WristRallyPhoneApp
        setContent {
            MaterialTheme(colorScheme = lightColorScheme()) {
                PhoneRoot(
                    service = app.service,
                    initialMatchId = deepLinkMatchId,
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkMatchId = matchIdFrom(intent)
    }

    private fun maybeRequestNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    companion object {
        const val EXTRA_MATCH_ID = "match_id"

        fun matchIdFrom(intent: Intent?): UUID? =
            intent?.getStringExtra(EXTRA_MATCH_ID)?.let { raw ->
                runCatching { UUID.fromString(raw) }.getOrNull()
            }
    }
}
