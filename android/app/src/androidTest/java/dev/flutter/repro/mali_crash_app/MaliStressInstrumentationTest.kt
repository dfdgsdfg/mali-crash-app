package dev.flutter.repro.mali_crash_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry.getArguments
import androidx.test.platform.app.InstrumentationRegistry.getInstrumentation
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MaliStressInstrumentationTest {
    @Test
    fun rotatesAndReturnsToForeground() {
        val device = UiDevice.getInstance(getInstrumentation())
        val appPackage = getInstrumentation().targetContext.packageName
        val scenario = scenarioArgument()
        MainActivity.clearCapturedTestLoopResult()
        try {
            launchScenario(appPackage, scenario)
            assertForeground(device, appPackage)

            var completed = 0
            for (iteration in 1..REPETITIONS) {
                if (iteration % 2 == 1) {
                    device.setOrientationLeft()
                } else {
                    device.setOrientationNatural()
                }
                SystemClock.sleep(SETTLE_MS)
                device.pressHome()
                assertTrue(
                    "App did not leave the foreground",
                    waitForPackageState(
                        device,
                        appPackage,
                        foreground = false,
                        timeoutMs = BACKGROUND_TIMEOUT_MS,
                    ),
                )
                SystemClock.sleep(SETTLE_MS)
                relaunchMainActivity(appPackage)
                assertForeground(device, appPackage)
                assertNoCapturedTestLoopResult(iteration)
                completed = iteration

                if (iteration % 10 == 0) {
                    Log.i(
                        TAG,
                        "scenario=$scenario completed=$completed orientation=" +
                            if (iteration % 2 == 1) "left" else "natural",
                    )
                }
            }
            Log.i(TAG, "scenario=$scenario completed=$completed")
            assertTrue(
                "Expected all rotation/lifecycle iterations to complete",
                completed == REPETITIONS,
            )
            assertNoCapturedTestLoopResult(completed)
        } finally {
            device.unfreezeRotation()
        }
    }

    private fun launchScenario(appPackage: String, scenario: Int) {
        val context: Context = getInstrumentation().targetContext
        val intent = Intent(TEST_LOOP_ACTION).apply {
            component = ComponentName(appPackage, MAIN_ACTIVITY_CLASS)
            type = "application/javascript"
            putExtra("scenario", scenario)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun relaunchMainActivity(appPackage: String) {
        val context: Context = getInstrumentation().targetContext
        val intent = Intent.makeMainActivity(
            ComponentName(appPackage, MAIN_ACTIVITY_CLASS),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        context.startActivity(intent)
    }

    private fun scenarioArgument(): Int {
        return getArguments().getString("scenario")?.toIntOrNull()
            ?: DEFAULT_SCENARIO
    }

    private fun assertForeground(device: UiDevice, appPackage: String) {
        assertTrue(
            "App did not return to foreground",
            waitForPackageState(
                device,
                appPackage,
                foreground = true,
                timeoutMs = FOREGROUND_TIMEOUT_MS,
            ),
        )
    }

    private fun assertNoCapturedTestLoopResult(iteration: Int) {
        val result = MainActivity.capturedTestLoopResult()
        assertTrue(
            "Test Loop result appeared after lifecycle cycle $iteration: $result",
            result == null,
        )
    }

    private fun waitForPackageState(
        device: UiDevice,
        appPackage: String,
        foreground: Boolean,
        timeoutMs: Long,
    ): Boolean {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        do {
            val isForeground = device.currentPackageName == appPackage
            if (isForeground == foreground) return true
            SystemClock.sleep(POLL_INTERVAL_MS)
        } while (SystemClock.uptimeMillis() < deadline)
        return false
    }

    companion object {
        private const val TAG = "MaliDriver"
        private const val MAIN_ACTIVITY_CLASS =
            "dev.flutter.repro.mali_crash_app.MainActivity"
        private const val TEST_LOOP_ACTION = "com.google.intent.action.TEST_LOOP"
        private const val DEFAULT_SCENARIO = 6
        private const val REPETITIONS = 30
        private const val SETTLE_MS = 250L
        private const val POLL_INTERVAL_MS = 50L
        private const val BACKGROUND_TIMEOUT_MS = 10_000L
        private const val FOREGROUND_TIMEOUT_MS = 10_000L

    }
}
