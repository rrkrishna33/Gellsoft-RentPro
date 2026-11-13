package com.gellsoft.gellsoft_rentpro

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // While staff logins are on, keep this app's preview out of the
        // recent-apps list (Android 13 and later). Screenshots still work.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gellsoft/privacy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hideRecentsPreview" -> {
                        val hide = call.argument<Boolean>("hide") ?: false
                        if (Build.VERSION.SDK_INT >= 33) {
                            setRecentsScreenshotEnabled(!hide)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Sends a PDF on WhatsApp: the file is read through a FileProvider (only
        // the cache/shared folder is ever shared), WhatsApp opens on the
        // customer's chat when a number is given, and the person presses send.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gellsoft/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendPdf" -> {
                        try {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("no file")
                            val number = call.argument<String>("number")
                            val text = call.argument<String>("text") ?: ""
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                File(path),
                            )
                            fun build(pkg: String?, withChat: Boolean): Intent =
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "application/pdf"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_TEXT, text)
                                    if (withChat && number != null) {
                                        putExtra("jid", "$number@s.whatsapp.net")
                                    }
                                    if (pkg != null) setPackage(pkg)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            var how = "chooser"
                            // WhatsApp, then WhatsApp Business
                            for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
                                try {
                                    startActivity(build(pkg, true))
                                    how = "whatsapp"
                                    break
                                } catch (e: ActivityNotFoundException) {
                                    // not installed: try the next one
                                }
                            }
                            if (how == "chooser") {
                                val chooser = Intent.createChooser(build(null, false), null)
                                chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(chooser)
                            }
                            result.success(how)
                        } catch (e: Exception) {
                            result.error("send_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

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
