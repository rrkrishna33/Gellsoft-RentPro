package com.gellsoft.gellsoft_rentpro

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Facts about the phone that the user cannot change by setting the date:
        // used to notice a changed clock (the monthly booking limit and the trial
        // depend on the date), and to recognise the phone so that reinstalling
        // the app does not restart the free trial.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gellsoft/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "clockInfo" -> {
                        val boot = try {
                            Settings.Global.getInt(contentResolver, "boot_count")
                        } catch (e: Exception) {
                            -1
                        }
                        val auto = try {
                            Settings.Global.getInt(contentResolver, Settings.Global.AUTO_TIME) == 1
                        } catch (e: Exception) {
                            null
                        }
                        result.success(
                            mapOf(
                                "elapsedMs" to SystemClock.elapsedRealtime(),
                                "bootCount" to boot,
                                "autoTime" to auto,
                            )
                        )
                    }
                    "deviceId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    "openDateSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_DATE_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (e: ActivityNotFoundException) {
                            // no such screen on this phone; the user can open it by hand
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
