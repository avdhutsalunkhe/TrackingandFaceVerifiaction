package com.fieldstaff.attendance.fieldstaff_attendance

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Handles device boot and app update events.
 * Recovers previously active tracking sessions subject to Android 12+ foreground service restrictions.
 */
class TrackingBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackingBootReceiver"
        private const val RECOVERY_CHANNEL_ID = "fieldstaff_recovery_channel"
        private const val RECOVERY_NOTIFICATION_ID = 9993
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "onReceive action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            checkAndRecoverSession(context)
        }
    }

    private fun checkAndRecoverSession(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val activeSessionUuid = prefs.getString("flutter.active_tracking_session_uuid", null)
        val activeDate = prefs.getString("flutter.active_tracking_date", null)

        val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

        if (activeSessionUuid != null && activeDate == todayStr) {
            Log.i(TAG, "Active tracking session found for today: $activeSessionUuid. Attempting recovery...")

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                // On Android < 12, directly restart foreground service
                try {
                    val serviceIntent = Intent(context, TrackingForegroundService::class.java).apply {
                        this.action = TrackingForegroundService.ACTION_START
                        putExtra(TrackingForegroundService.EXTRA_SESSION_UUID, activeSessionUuid)
                    }
                    ContextCompat.startForegroundService(context, serviceIntent)
                    Log.i(TAG, "Foreground service started directly after reboot (Android < 12)")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start foreground service on boot: $e")
                    showRecoveryNotification(context, activeSessionUuid)
                }
            } else {
                // Android 12+ restricts background foreground-service starts from receivers.
                // Show high-priority notification to resume on user tap (100% compliant with Google Play policy).
                showRecoveryNotification(context, activeSessionUuid)
            }
        } else {
            Log.i(TAG, "No eligible active session for today to recover.")
        }
    }

    private fun showRecoveryNotification(context: Context, sessionUuid: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                RECOVERY_CHANNEL_ID,
                "Session Recovery Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts to resume active duty travel tracking after reboot"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("resume_session_uuid", sessionUuid)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            RECOVERY_NOTIFICATION_ID,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, RECOVERY_CHANNEL_ID)
            .setContentTitle("Active Duty Tracking Session Pending")
            .setContentText("Tap to resume your duty travel route recording.")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(RECOVERY_NOTIFICATION_ID, notification)
        Log.i(TAG, "Recovery notification posted for user to resume tracking session.")
    }
}
