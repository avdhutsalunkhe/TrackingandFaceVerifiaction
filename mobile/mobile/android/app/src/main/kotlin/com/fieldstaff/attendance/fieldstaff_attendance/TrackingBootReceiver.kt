package com.fieldstaff.attendance.fieldstaff_attendance

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Handles device boot, scheduled start/stop alarms, and watchdog checks.
 * Ensures tracking starts at 08:00 AM (or runs 24*7 continuous), stops at 06:00 PM,
 * and recovers seamlessly across reboots without employee interaction.
 */
class TrackingBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TrackingBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val action = intent.action
            Log.i(TAG, "onReceive action: $action")

            when (action) {
                Intent.ACTION_BOOT_COMPLETED,
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON",
                Intent.ACTION_MY_PACKAGE_REPLACED,
                TrackingScheduler.ACTION_START_SCHEDULED,
                TrackingScheduler.ACTION_STOP_SCHEDULED,
                TrackingScheduler.ACTION_WATCHDOG -> {
                    Log.i(TAG, "Evaluating and reconciling tracking schedule for action: $action")
                    TrackingScheduler.evaluateAndSchedule(context)
                }
                else -> {
                    Log.i(TAG, "Unhandled action: $action")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "TrackingBootReceiver onReceive error: $e")
        }
    }
}
