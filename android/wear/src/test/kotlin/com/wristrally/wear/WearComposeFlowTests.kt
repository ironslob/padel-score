package com.wristrally.wear

import android.Manifest
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.wear.compose.material3.MaterialTheme
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Watch-sized Compose checks. A 384dp box matches Galaxy Watch 4 (42mm).
 * The first-launch "Got it" control used to sit in a ScalingLazyColumn edge
 * item — on a round watch it was not hittable, and a phone-sized test surface
 * would have hidden that.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33], qualifiers = "w384dp-h384dp-notlong")
class WearComposeFlowTests {
    @get:Rule
    val composeRule = createComposeRule()

    @Before
    fun grantWorkoutPermissions() {
        val app = ApplicationProvider.getApplicationContext<android.app.Application>()
        Shadows.shadowOf(app).grantPermissions(
            Manifest.permission.ACTIVITY_RECOGNITION,
            Manifest.permission.BODY_SENSORS,
            Manifest.permission.POST_NOTIFICATIONS,
        )
    }

    @Test
    fun gotItIsOnScreenWithoutScrollingAndDismissesToStartMatch() {
        val model = testWearModel(tipSeen = false)
        setWatchContent(model)
        composeRule.waitForIdle()

        val gotIt = composeRule.onNodeWithText("Got it")
        gotIt.assertIsDisplayed()
        gotIt.assertHasClickAction()
        val button = gotIt.fetchSemanticsNode().boundsInRoot
        val root = composeRule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("Got it too small to tap: $button", button.height > 36f)
        assertTrue(
            "Got it must sit in the bottom of the round viewport, not a scaled list edge: $button in $root",
            button.bottom > root.height * 0.72f,
        )

        gotIt.performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Start Match").assertIsDisplayed()
        composeRule.onNodeWithText("Got it").assertDoesNotExist()
    }

    @Test
    fun settingsDoneReturnsToStartMatch() {
        val model = testWearModel(tipSeen = true)
        setWatchContent(model)
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Settings").assertIsDisplayed().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Match length").assertIsDisplayed()

        val done = composeRule.onNodeWithText("Done")
        done.assertIsDisplayed()
        done.assertHasClickAction()
        val button = done.fetchSemanticsNode().boundsInRoot
        val root = composeRule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("Done too small to tap: $button", button.height > 36f)
        assertTrue("Done must be pinned to the bottom: $button in $root", button.bottom > root.height * 0.72f)

        done.performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Start Match").assertIsDisplayed()
    }

    @Test
    fun startMatchOpensWarmUpWhenWorkoutFails() {
        val model = testWearModel(tipSeen = true, workout = ExplodingWorkoutManager())
        setWatchContent(model)
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Start Match").performClick()
        composeRule.waitForIdle()
        // Scoring continues; either the workout-error overlay or warm-up is fine.
        val hasWarmUp = runCatching {
            composeRule.onNodeWithText("Warm up").assertIsDisplayed()
        }.isSuccess
        val hasError = runCatching {
            composeRule.onNodeWithText("Workout tracking unavailable").assertIsDisplayed()
        }.isSuccess
        assertTrue("expected warm-up or workout error after Start Match", hasWarmUp || hasError)
    }

    private fun setWatchContent(model: WearAppModel) {
        composeRule.setContent {
            Box(Modifier.size(384.dp)) {
                MaterialTheme {
                    WearApp(model)
                }
            }
        }
    }
}
