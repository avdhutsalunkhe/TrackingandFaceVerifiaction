package com.fieldstaff.attendance.fieldstaff_attendance

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.fieldstaff.attendance/background_tracking"
        private const val EVENT_CHANNEL = "com.fieldstaff.attendance/background_tracking_events"
        private const val UPDATE_CHANNEL = "com.fieldstaff.attendance/app_update"
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup MethodChannel for native service commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val fine = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val coarse = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    if (!fine && !coarse) {
                        result.error("PERMISSION_DENIED", "Location permissions are not yet granted by user", null)
                        return@setMethodCallHandler
                    }

                    val sessionUuid = call.argument<String>("session_uuid")
                    val userId = call.argument<Int>("user_id") ?: 0
                    val attendanceId = call.argument<Int>("attendance_id") ?: 0
                    val date = call.argument<String>("date")

                    val intent = Intent(this, TrackingForegroundService::class.java).apply {
                        action = TrackingForegroundService.ACTION_START
                        putExtra(TrackingForegroundService.EXTRA_SESSION_UUID, sessionUuid)
                        putExtra(TrackingForegroundService.EXTRA_USER_ID, userId)
                        putExtra(TrackingForegroundService.EXTRA_ATTENDANCE_ID, attendanceId)
                        putExtra(TrackingForegroundService.EXTRA_DATE, date)
                    }

                    try {
                        ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_FAILED", e.message, null)
                    }
                }
                "stopService" -> {
                    val intent = Intent(this, TrackingForegroundService::class.java).apply {
                        action = TrackingForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "pauseService" -> {
                    val intent = Intent(this, TrackingForegroundService::class.java).apply {
                        action = TrackingForegroundService.ACTION_PAUSE
                    }
                    startService(intent)
                    result.success(true)
                }
                "resumeService" -> {
                    val intent = Intent(this, TrackingForegroundService::class.java).apply {
                        action = TrackingForegroundService.ACTION_RESUME
                    }
                    startService(intent)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(TrackingForegroundService.isServiceRunning)
                }
                "scheduleTracking" -> {
                    val userId = call.argument<Int>("user_id") ?: 0
                    val is24x7 = call.argument<Boolean>("is_24x7") ?: true
                    val startTime = call.argument<String>("start_time") ?: "08:00"
                    val endTime = call.argument<String>("end_time") ?: "18:00"
                    val timezone = call.argument<String>("timezone") ?: "Asia/Kolkata"

                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putLong("flutter.user_id", userId.toLong())
                        .putBoolean("flutter.tracking_mode_24x7", is24x7)
                        .putString("flutter.tracking_schedule_start", startTime)
                        .putString("flutter.tracking_schedule_end", endTime)
                        .putString("flutter.tracking_timezone", timezone)
                        .apply()

                    TrackingScheduler.evaluateAndSchedule(this)
                    result.success(true)
                }
                "evaluateSchedule" -> {
                    TrackingScheduler.evaluateAndSchedule(this)
                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true)
                    }
                }
                "requestBatteryOptimizationExemption" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "Failed to show battery optimization dialog: $e")
                    }
                    result.success(true)
                }
                "getDiagnostics" -> {
                    val pm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else true

                    val diag = mapOf(
                        "is_service_running" to TrackingForegroundService.isServiceRunning,
                        "battery_optimization_ignored" to pm,
                        "android_sdk" to Build.VERSION.SDK_INT,
                        "device_manufacturer" to Build.MANUFACTURER,
                        "device_model" to Build.MODEL
                    )
                    result.success(diag)
                }
                else -> result.notImplemented()
            }
        }

        // Setup EventChannel for streaming background GPS fixes to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    TrackingForegroundService.locationEventListener = { pointMap ->
                        runOnUiThread {
                            eventSink?.success(pointMap)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    TrackingForegroundService.locationEventListener = null
                }
            }
        )

        // Setup MethodChannel for Developer-Controlled App Update & Package Installation
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDistributionChannel" -> {
                    try {
                        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getInstallerPackageName(packageName)
                        }
                        if (installer == "com.android.vending") {
                            result.success("google_play")
                        } else {
                            result.success("direct_apk")
                        }
                    } catch (e: Exception) {
                        result.success("direct_apk")
                    }
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_OPEN_FAILED", e.message, null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "File path cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    val apkFile = File(filePath)
                    if (!apkFile.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }

                    try {
                        // Strict Security: Verify APK package name matches app
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageArchiveInfo(filePath, PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageArchiveInfo(filePath, 0)
                        }

                        if (packageInfo != null && packageInfo.packageName != packageName) {
                            result.error(
                                "PACKAGE_MISMATCH",
                                "Security rejection: APK package '${packageInfo.packageName}' does not match installed application '$packageName'",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        // Create Content URI via FileProvider
                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile
                        )

                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        startActivity(installIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                "isNetworkUnmetered" -> {
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val network = cm.activeNetwork
                        val capabilities = cm.getNetworkCapabilities(network)
                        val isUnmetered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true
                        result.success(isUnmetered)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

