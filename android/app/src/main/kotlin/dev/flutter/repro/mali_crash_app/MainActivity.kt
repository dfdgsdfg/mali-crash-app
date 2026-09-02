package dev.flutter.repro.mali_crash_app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var pendingCycle: PendingCycle? = null

    private class PendingCycle(
        val result: MethodChannel.Result,
        val taskId: Int,
    ) {
        var restoreRequested = false
        var focusConfirmed = false
        var restoreTimeout: Runnable? = null
        var settle: Runnable? = null
        var completed = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchConfig" -> result.success(
                    mapOf(
                        "isTestLoop" to (intent?.action == TEST_LOOP_ACTION),
                        "scenario" to (intent?.getIntExtra("scenario", 0) ?: 0),
                    ),
                )

                "getDeviceInfo" -> result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "device" to Build.DEVICE,
                        "hardware" to Build.HARDWARE,
                        "sdk" to Build.VERSION.SDK_INT,
                    ),
                )

                "cycleTask" -> {
                    if (pendingCycle != null) {
                        result.error(
                            "CYCLE_TASK_BUSY",
                            "A task cycle is already pending",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val capturedTaskId = taskId
                    if (capturedTaskId < 0) {
                        result.error(
                            "CYCLE_TASK_INVALID",
                            "Could not capture the current task id",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    val cycle = PendingCycle(result, capturedTaskId)
                    pendingCycle = cycle
                    val movedToBack = try {
                        moveTaskToBack(true)
                    } catch (error: Exception) {
                        Log.e(TAG, "cycleTask background failed taskId=$capturedTaskId", error)
                        failCycle(
                            cycle,
                            "CYCLE_TASK_BACKGROUND_FAILED",
                            error.message ?: "Could not move task to back",
                        )
                        return@setMethodCallHandler
                    }
                    if (!movedToBack) {
                        Log.e(TAG, "cycleTask background failed taskId=$capturedTaskId")
                        failCycle(
                            cycle,
                            "CYCLE_TASK_BACKGROUND_FAILED",
                            "moveTaskToBack returned false",
                        )
                        return@setMethodCallHandler
                    }
                    Log.i(TAG, "cycleTask background taskId=$capturedTaskId")

                    val activityManager = getSystemService(Context.ACTIVITY_SERVICE)
                        as? ActivityManager
                    if (activityManager == null) {
                        failCycle(
                            cycle,
                            "CYCLE_TASK_FRONT_FAILED",
                            "ActivityManager is unavailable",
                        )
                        return@setMethodCallHandler
                    }

                    val scheduled = handler.postDelayed({
                        if (pendingCycle !== cycle) return@postDelayed
                        cycle.restoreRequested = true
                        Log.i(TAG, "cycleTask restore-requested taskId=$capturedTaskId")
                        try {
                            activityManager.moveTaskToFront(
                                capturedTaskId,
                                ActivityManager.MOVE_TASK_WITH_HOME,
                            )
                        } catch (error: Exception) {
                            Log.e(
                                TAG,
                                "cycleTask restore failed taskId=$capturedTaskId",
                                error,
                            )
                            failCycle(
                                cycle,
                                "CYCLE_TASK_FRONT_FAILED",
                                error.message ?: "Could not move task to front",
                            )
                            return@postDelayed
                        }
                        val timeout = Runnable {
                            Log.e(TAG, "cycleTask timeout taskId=$capturedTaskId")
                            failCycle(
                                cycle,
                                "CYCLE_TASK_FRONT_TIMEOUT",
                                "Task did not regain window focus",
                            )
                        }
                        cycle.restoreTimeout = timeout
                        if (!handler.postDelayed(timeout, RESTORE_TIMEOUT_MS)) {
                            Log.e(
                                TAG,
                                "cycleTask timeout scheduling failed taskId=$capturedTaskId",
                            )
                            failCycle(
                                cycle,
                                "CYCLE_TASK_FRONT_FAILED",
                                "Could not schedule task restore timeout",
                            )
                        }
                    }, BACKGROUND_DELAY_MS)
                    if (!scheduled) {
                        Log.e(
                            TAG,
                            "cycleTask background scheduling failed taskId=$capturedTaskId",
                        )
                        failCycle(
                            cycle,
                            "CYCLE_TASK_FRONT_FAILED",
                            "Could not schedule task restore",
                        )
                    }
                }

                "log" -> {
                    Log.i(TAG, call.arguments?.toString().orEmpty())
                    result.success(null)
                }

                "finishTestLoop" -> {
                    val json = JSONObject.wrap(call.arguments)?.toString() ?: "{}"
                    captureTestLoopResult(json)
                    val outputUri = intent?.data
                    if (outputUri != null) {
                        contentResolver.openOutputStream(outputUri, "w")
                            ?.bufferedWriter()
                            ?.use { it.write(json) }
                    }
                    result.success(null)
                    handler.post { finish() }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val cycle = pendingCycle ?: return
        if (!hasFocus || !cycle.restoreRequested || cycle.focusConfirmed) return

        cycle.focusConfirmed = true
        Log.i(TAG, "cycleTask focus-confirmed taskId=${cycle.taskId}")
        val settle = Runnable {
            if (pendingCycle === cycle) {
                Log.i(TAG, "cycleTask restored-settled taskId=${cycle.taskId}")
                completeCycle(cycle)
            }
        }
        cycle.settle = settle
        if (!handler.postDelayed(settle, SETTLE_DELAY_MS)) {
            failCycle(
                cycle,
                "CYCLE_TASK_FRONT_FAILED",
                "Could not schedule task settle",
            )
        }
    }

    private fun completeCycle(cycle: PendingCycle) {
        if (pendingCycle !== cycle || cycle.completed) return
        cycle.completed = true
        cycle.restoreTimeout?.let(handler::removeCallbacks)
        cycle.settle?.let(handler::removeCallbacks)
        pendingCycle = null
        cycle.result.success(null)
    }

    private fun failCycle(cycle: PendingCycle, code: String, message: String) {
        if (pendingCycle !== cycle || cycle.completed) return
        cycle.completed = true
        cycle.restoreTimeout?.let(handler::removeCallbacks)
        cycle.settle?.let(handler::removeCallbacks)
        pendingCycle = null
        cycle.result.error(code, message, null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    companion object {
        private const val CHANNEL = "dev.flutter.repro/mali_crash"
        private const val TEST_LOOP_ACTION = "com.google.intent.action.TEST_LOOP"
        private const val TAG = "MaliRepro"
        private const val BACKGROUND_DELAY_MS = 180L
        private const val SETTLE_DELAY_MS = 120L
        private const val RESTORE_TIMEOUT_MS = 3000L
        private val testLoopResultLock = Any()
        private var capturedTestLoopResult: String? = null

        fun clearCapturedTestLoopResult() {
            synchronized(testLoopResultLock) {
                capturedTestLoopResult = null
            }
        }

        fun capturedTestLoopResult(): String? {
            return synchronized(testLoopResultLock) {
                capturedTestLoopResult
            }
        }

        private fun captureTestLoopResult(json: String) {
            synchronized(testLoopResultLock) {
                capturedTestLoopResult = json
            }
            Log.i(TAG, "finishTestLoop result=$json")
        }
    }
}
