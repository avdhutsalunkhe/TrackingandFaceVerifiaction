package com.fieldstaff.attendance.fieldstaff_attendance

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Native Android scheduler for automatic 24*7 continuous and daily 08:00 AM – 06:00 PM
 * location tracking. Handles start/stop alarms, boot recovery, and process restart watchdog.
 */
object TrackingScheduler {
    private const val TAG = "TrackingScheduler"

    const val ACTION_START_SCHEDULED = "ACTION_START_SCHEDULED_WINDOW"
    const val ACTION_STOP_SCHEDULED = "ACTION_STOP_SCHEDULED_WINDOW"
    const val ACTION_WATCHDOG = "ACTION_TRACKING_WATCHDOG"

    const val REQUEST_CODE_START = 1001
    const val REQUEST_CODE_STOP = 1002
    const val REQUEST_CODE_WATCHDOG = 1003

    fun evaluateAndSchedule(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val userId = prefs.getLong("flutter.user_id", 0L).toInt()
        val travelMapEnabled = prefs.getBoolean("flutter.travel_map_enabled", true)
        val is24x7 = prefs.getBoolean("flutter.tracking_mode_24x7", true) // Default 24*7 continuous mode
        val startTimeStr = prefs.getString("flutter.tracking_schedule_start", "08:00") ?: "08:00"
        val endTimeStr = prefs.getString("flutter.tracking_schedule_end", "18:00") ?: "18:00"
        val tzId = prefs.getString("flutter.tracking_timezone", "Asia/Kolkata") ?: "Asia/Kolkata"

        Log.i(TAG, "evaluateAndSchedule: userId=$userId, travelMapEnabled=$travelMapEnabled, is24x7=$is24x7, schedule=$startTimeStr-$endTimeStr ($tzId)")

        if (userId <= 0 || !travelMapEnabled) {
            Log.i(TAG, "Tracking disabled or user not logged in. Stopping service.")
            stopTracking(context)
            cancelAlarms(context)
            return
        }

        val tz = TimeZone.getTimeZone(tzId)
        val nowCal = Calendar.getInstance(tz)

        if (is24x7) {
            // 24x7 continuous duty tracking mode
            Log.i(TAG, "24*7 continuous tracking mode active. Ensuring foreground service is running.")
            startTracking(context)
            scheduleMidnightRollover(context, tz)
            scheduleWatchdog(context)
            return
        }

        // Daily 08:00 AM – 06:00 PM Schedule mode
        val startParts = startTimeStr.split(":").map { it.toIntOrNull() ?: 0 }
        val endParts = endTimeStr.split(":").map { it.toIntOrNull() ?: 0 }

        val startCal = Calendar.getInstance(tz).apply {
            set(Calendar.HOUR_OF_DAY, startParts.getOrElse(0) { 8 })
            set(Calendar.MINUTE, startParts.getOrElse(1) { 0 })
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val endCal = Calendar.getInstance(tz).apply {
            set(Calendar.HOUR_OF_DAY, endParts.getOrElse(0) { 18 })
            set(Calendar.MINUTE, endParts.getOrElse(1) { 0 })
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val nowMs = nowCal.timeInMillis
        val startMs = startCal.timeInMillis
        val endMs = endCal.timeInMillis

        if (nowMs in startMs until endMs) {
            // Within tracking window (08:00 – 18:00)
            Log.i(TAG, "Current time is within scheduled tracking window ($startTimeStr – $endTimeStr). Starting service.")
            startTracking(context)
            scheduleAlarm(context, endMs, ACTION_STOP_SCHEDULED, REQUEST_CODE_STOP)
            scheduleWatchdog(context)
        } else if (nowMs < startMs) {
            // Before 08:00 AM
            Log.i(TAG, "Current time is before window. Scheduling start at $startTimeStr.")
            stopTracking(context)
            scheduleAlarm(context, startMs, ACTION_START_SCHEDULED, REQUEST_CODE_START)
        } else {
            // After 06:00 PM -> Schedule next day's 08:00 AM
            Log.i(TAG, "Current time is after window. Scheduling start for tomorrow.")
            stopTracking(context)
            startCal.add(Calendar.DAY_OF_YEAR, 1)
            scheduleAlarm(context, startCal.timeInMillis, ACTION_START_SCHEDULED, REQUEST_CODE_START)
        }
    }

    fun startTracking(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val userId = prefs.getLong("flutter.user_id", 0L).toInt()
        if (userId <= 0) {
            Log.w(TAG, "Cannot start tracking: userId is 0")
            return
        }

        val tzId = prefs.getString("flutter.tracking_timezone", "Asia/Kolkata") ?: "Asia/Kolkata"
        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(tzId)
        }.format(Date())

        var activeUuid = prefs.getString("flutter.active_tracking_session_uuid", null)
        val activeDate = prefs.getString("flutter.active_tracking_date", null)

        if (activeUuid == null || activeDate != todayStr) {
            val punchId = System.currentTimeMillis()
            activeUuid = "TRACK_${userId}_${todayStr}_AUTO_${punchId}"
            prefs.edit()
                .putString("flutter.active_tracking_session_uuid", activeUuid)
                .putLong("flutter.active_tracking_user_id", userId.toLong())
                .putLong("flutter.active_tracking_attendance_id", punchId)
                .putString("flutter.active_tracking_date", todayStr)
                .apply()
            Log.i(TAG, "Created daily tracking session: $activeUuid")
        }

        val serviceIntent = Intent(context, TrackingForegroundService::class.java).apply {
            action = TrackingForegroundService.ACTION_START
            putExtra(TrackingForegroundService.EXTRA_SESSION_UUID, activeUuid)
            putExtra(TrackingForegroundService.EXTRA_USER_ID, userId)
            putExtra(TrackingForegroundService.EXTRA_DATE, todayStr)
        }

        try {
            ContextCompat.startForegroundService(context, serviceIntent)
            Log.i(TAG, "Started TrackingForegroundService successfully for session $activeUuid")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start TrackingForegroundService: $e")
        }
    }

    fun stopTracking(context: Context) {
        if (!TrackingForegroundService.isServiceRunning) return
        val serviceIntent = Intent(context, TrackingForegroundService::class.java).apply {
            action = TrackingForegroundService.ACTION_STOP
        }
        try {
            context.startService(serviceIntent)
            Log.i(TAG, "Stopped TrackingForegroundService cleanly")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping TrackingForegroundService: $e")
        }
    }

    private fun scheduleAlarm(context: Context, triggerAtMs: Long, action: String, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, TrackingBootReceiver::class.java).apply {
            this.action = action
        }
        val pIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pIntent)
            }
            val timeStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(triggerAtMs))
            Log.i(TAG, "Scheduled alarm [$action] for $timeStr")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule alarm: $e")
        }
    }

    private fun scheduleWatchdog(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, TrackingBootReceiver::class.java).apply {
            this.action = ACTION_WATCHDOG
        }
        val pIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_WATCHDOG,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val nextHourMs = System.currentTimeMillis() + (60 * 60 * 1000L) // every 1 hour
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextHourMs, pIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, nextHourMs, pIntent)
            }
        } catch (_: Exception) {}
    }

    private fun scheduleMidnightRollover(context: Context, tz: TimeZone) {
        val cal = Calendar.getInstance(tz).apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }
        scheduleAlarm(context, cal.timeInMillis, ACTION_START_SCHEDULED, REQUEST_CODE_START)
    }

    private fun cancelAlarms(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val startIntent = Intent(context, TrackingBootReceiver::class.java).apply { action = ACTION_START_SCHEDULED }
        val pStart = PendingIntent.getBroadcast(context, REQUEST_CODE_START, startIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarmManager.cancel(pStart)

        val stopIntent = Intent(context, TrackingBootReceiver::class.java).apply { action = ACTION_STOP_SCHEDULED }
        val pStop = PendingIntent.getBroadcast(context, REQUEST_CODE_STOP, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarmManager.cancel(pStop)
    }
}
