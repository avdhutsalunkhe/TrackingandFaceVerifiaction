package com.fieldstaff.attendance.fieldstaff_attendance

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Dedicated, persistent Android Foreground Service for continuous employee travel tracking.
 * Runs independently of Flutter UI lifecycle, maintains partial wake lock, collects GPS fixes,
 * persists coordinates to SQLite, and updates ongoing notification.
 */
class TrackingForegroundService : Service(), LocationListener {

    companion object {
        private const val TAG = "TrackingFgService"
        const val CHANNEL_ID = "fieldstaff_tracking_service_channel"
        const val NOTIFICATION_ID = 9991

        const val ACTION_START = "ACTION_START_TRACKING"
        const val ACTION_STOP = "ACTION_STOP_TRACKING"
        const val ACTION_PAUSE = "ACTION_PAUSE_TRACKING"
        const val ACTION_RESUME = "ACTION_RESUME_TRACKING"

        const val EXTRA_SESSION_UUID = "extra_session_uuid"
        const val EXTRA_USER_ID = "extra_user_id"
        const val EXTRA_ATTENDANCE_ID = "extra_attendance_id"
        const val EXTRA_DATE = "extra_date"

        // Thread-safe listener for forwarding locations to Flutter when UI is active
        var locationEventListener: ((Map<String, Any?>) -> Unit)? = null
        var isServiceRunning: Boolean = false
            private set
    }

    private var locationManager: LocationManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var sessionUuid: String? = null
    private var userId: Int = 0
    private var sequenceNumber: Int = 1
    private var totalDistanceMeters: Double = 0.0

    private var lastLat: Double? = null
    private var lastLng: Double? = null
    private var lastFixTimeMs: Long = 0L

    private var isPaused: Boolean = false
    private var db: SQLiteDatabase? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "TrackingForegroundService onCreate")
        createNotificationChannel()
        acquireWakeLock()
        initDatabase()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.i(TAG, "onStartCommand action: $action")

        when (action) {
            ACTION_STOP -> {
                stopTrackingSession()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                pauseTracking()
                return START_STICKY
            }
            ACTION_RESUME -> {
                resumeTracking()
                return START_STICKY
            }
            ACTION_START -> {
                // Read extras or fallback to FlutterSharedPreferences
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                sessionUuid = intent?.getStringExtra(EXTRA_SESSION_UUID)
                    ?: prefs.getString("flutter.active_tracking_session_uuid", null)

                userId = intent?.getIntExtra(EXTRA_USER_ID, 0)
                    ?: (prefs.getLong("flutter.active_tracking_user_id", 0L).toInt())

                totalDistanceMeters = prefs.getFloat("flutter.active_tracking_distance", 0.0f).toDouble()

                if (sessionUuid == null) {
                    Log.w(TAG, "No active session UUID found in intent or preferences. Stopping service.")
                    stopSelf()
                    return START_NOT_STICKY
                }

                // Restore last known coordinates and sequence number from SQLite
                restoreStateFromDb()

                // Start Foreground with proper Android 14 location type
                startForegroundWithNotification("Tracking started. Acquiring GPS fixes...")

                // Request location updates
                startLocationUpdates()
                isServiceRunning = true
            }
        }

        // Return START_STICKY to allow Android process recreation after memory pressure
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FieldStaff Travel Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Continuous employee journey GPS tracking"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(status: String, detailText: String? = null, accuracyMeters: Float? = null): Notification {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val is24x7 = prefs.getBoolean("flutter.tracking_mode_24x7", true)
        val startTimeStr = prefs.getString("flutter.tracking_schedule_start", "08:00 AM") ?: "08:00 AM"
        val endTimeStr = prefs.getString("flutter.tracking_schedule_end", "06:00 PM") ?: "06:00 PM"
        val scheduleDisplay = if (is24x7) "24*7 Continuous" else "$startTimeStr – $endTimeStr"

        val timeFormat = SimpleDateFormat("hh:mm a", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Kolkata")
        }
        val lastFixStr = if (lastFixTimeMs > 0L) timeFormat.format(Date(lastFixTimeMs)) else "Acquiring fix..."
        val distKm = totalDistanceMeters / 1000.0

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = when (status) {
            "Active" -> "Schedule: $scheduleDisplay • Last GPS: $lastFixStr"
            "Interrupted" -> detailText ?: "Location permissions or GPS unavailable"
            "Paused" -> "Tracking paused • %.2f km".format(distKm)
            else -> detailText ?: "Duty GPS Tracking"
        }

        val accuracyStr = if (accuracyMeters != null) " (±${accuracyMeters.toInt()}m)" else ""
        val bigText = """
            Status: $status
            Schedule: $scheduleDisplay
            Last GPS update: $lastFixStr$accuracyStr
            Total Travel: %.2f km
        """.trimIndent().format(distKm)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Field Duty Tracking")
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(status == "Active" || status == "Interrupted")
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun startForegroundWithNotification(contentText: String) {
        val notification = buildNotification(status = "Active", detailText = contentText)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(status: String = "Active", detailText: String? = null, accuracyMeters: Float? = null) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildNotification(status, detailText, accuracyMeters)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "FieldStaff::BackgroundGpsWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire(12 * 60 * 60 * 1000L) // 12 hours max safety timeout
            }
            Log.i(TAG, "Partial wake lock acquired")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.i(TAG, "Partial wake lock released")
            }
        }
        wakeLock = null
    }

    private fun initDatabase() {
        try {
            val dbPath = getDatabasePath("fieldstaff_tracking_offline.db")
            if (dbPath.exists()) {
                db = SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READWRITE)
                Log.i(TAG, "Connected to SQLite database: ${dbPath.path}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error opening SQLite database: $e")
        }
    }

    private fun restoreStateFromDb() {
        val sUuid = sessionUuid ?: return
        try {
            db?.let { database ->
                // Query max sequence number
                val cursor = database.rawQuery(
                    "SELECT MAX(sequence_number) FROM offline_route_points WHERE session_uuid = ?",
                    arrayOf(sUuid)
                )
                if (cursor.moveToFirst()) {
                    val maxSeq = cursor.getInt(0)
                    if (maxSeq > 0) {
                        sequenceNumber = maxSeq + 1
                    }
                }
                cursor.close()

                // Query last point
                val ptCursor = database.rawQuery(
                    "SELECT latitude, longitude, recorded_at FROM offline_route_points WHERE session_uuid = ? ORDER BY sequence_number DESC LIMIT 1",
                    arrayOf(sUuid)
                )
                if (ptCursor.moveToFirst()) {
                    lastLat = ptCursor.getDouble(0)
                    lastLng = ptCursor.getDouble(1)
                }
                ptCursor.close()

                // Query session distance
                val sessCursor = database.rawQuery(
                    "SELECT total_distance_meters FROM offline_sessions WHERE session_uuid = ?",
                    arrayOf(sUuid)
                )
                if (sessCursor.moveToFirst()) {
                    totalDistanceMeters = sessCursor.getDouble(0)
                }
                sessCursor.close()
                Log.i(TAG, "State restored for $sUuid: seq=$sequenceNumber, dist=${totalDistanceMeters}m, lastPos=($lastLat, $lastLng)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore state from SQLite: $e")
        }
    }

    private fun startLocationUpdates() {
        try {
            locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

            val isGpsEnabled = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true
            val isNetworkEnabled = locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true

            if (!isGpsEnabled && !isNetworkEnabled) {
                Log.w(TAG, "Both GPS and Network location providers are disabled!")
                broadcastHealthEvent("GPS_DISABLED", "Location services disabled on device")
                return
            }

            // Register continuous GPS updates: 3000ms, 0 meters
            if (isGpsEnabled) {
                locationManager?.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    3000L,
                    0f,
                    this
                )
                Log.i(TAG, "Registered GPS_PROVIDER updates (3s, 0m)")
            }

            // Also register NETWORK_PROVIDER as fallback
            if (isNetworkEnabled) {
                locationManager?.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    10000L,
                    0f,
                    this
                )
                Log.i(TAG, "Registered NETWORK_PROVIDER fallback updates (10s, 0m)")
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException requesting location updates: $e")
            broadcastHealthEvent("PERMISSION_DENIED", "SecurityException: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Exception requesting location updates: $e")
        }
    }

    override fun onLocationChanged(loc: Location) {
        if (isPaused || sessionUuid == null) return

        val lat = loc.latitude
        val lng = loc.longitude
        val accuracy = loc.accuracy

        // Stage 1: Validate coordinate bounds and Null Island
        if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) return
        if (Math.abs(lat) < 1e-6 && Math.abs(lng) < 1e-6) return

        // Stage 2: Filter low accuracy (> 65 meters)
        if (accuracy > 65.0f) {
            Log.d(TAG, "Fix dropped due to poor accuracy: ${accuracy}m > 65m")
            return
        }

        val nowMs = System.currentTimeMillis()
        val sUuid = sessionUuid!!

        // Calculate displacement
        var stepDist = 0.0
        if (lastLat != null && lastLng != null) {
            stepDist = haversineDistanceMeters(lastLat!!, lastLng!!, lat, lng)
            val elapsedSec = (nowMs - lastFixTimeMs) / 1000.0

            // Speed sanity check (~198 km/h max = 55 m/s)
            if (elapsedSec > 0.5 && stepDist > 40.0) {
                val speed = stepDist / elapsedSec
                if (speed > 55.0) {
                    Log.w(TAG, "Implied speed too high (${speed}m/s), dropping jump")
                    return
                }
            }
        }

        // Commit distance if displacement >= 8.0 meters
        if (stepDist >= 8.0) {
            totalDistanceMeters += stepDist
            lastLat = lat
            lastLng = lng
            lastFixTimeMs = nowMs

            // Update SharedPreferences for Flutter
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putFloat("flutter.active_tracking_distance", totalDistanceMeters.toFloat()).apply()
        } else if (lastLat == null) {
            lastLat = lat
            lastLng = lng
            lastFixTimeMs = nowMs
        }

        val seq = sequenceNumber++
        val clientPointId = "${sUuid}_pt_${seq}_${nowMs}"
        val isoTimestamp = formatIsoUtc(Date(loc.time))

        // Stage 3: Persist directly to local SQLite
        persistPointToDb(
            sessionUuid = sUuid,
            clientPointId = clientPointId,
            sequenceNumber = seq,
            latitude = lat,
            longitude = lng,
            accuracy = accuracy.toDouble(),
            altitude = loc.altitude,
            speed = if (loc.hasSpeed()) loc.speed.toDouble() else null,
            bearing = if (loc.hasBearing()) loc.bearing.toDouble() else null,
            recordedAt = isoTimestamp
        )

        // Update notification with new status
        updateNotification(status = "Active", accuracyMeters = accuracy)

        // Stage 4: Forward to Flutter live stream if engine is attached
        val pointMap = mapOf<String, Any?>(
            "session_uuid" to sUuid,
            "client_point_id" to clientPointId,
            "sequence_number" to seq,
            "latitude" to lat,
            "longitude" to lng,
            "accuracy_meters" to accuracy.toDouble(),
            "altitude_meters" to loc.altitude,
            "speed_mps" to (if (loc.hasSpeed()) loc.speed.toDouble() else null),
            "bearing_degrees" to (if (loc.hasBearing()) loc.bearing.toDouble() else null),
            "recorded_at" to isoTimestamp,
            "total_distance_meters" to totalDistanceMeters
        )
        locationEventListener?.invoke(pointMap)
    }

    private fun persistPointToDb(
        sessionUuid: String,
        clientPointId: String,
        sequenceNumber: Int,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        altitude: Double?,
        speed: Double?,
        bearing: Double?,
        recordedAt: String
    ) {
        if (db == null || !db!!.isOpen) {
            initDatabase()
        }
        db?.let { database ->
            try {
                val cv = ContentValues().apply {
                    put("session_uuid", sessionUuid)
                    put("client_point_id", clientPointId)
                    put("sequence_number", sequenceNumber)
                    put("latitude", latitude)
                    put("longitude", longitude)
                    put("accuracy_meters", accuracy)
                    if (altitude != null) put("altitude_meters", altitude)
                    if (speed != null) put("speed_mps", speed)
                    if (bearing != null) put("bearing_degrees", bearing)
                    put("recorded_at", recordedAt)
                    put("is_gap", 0)
                    put("sync_status", "PENDING")
                }
                database.insertWithOnConflict(
                    "offline_route_points",
                    null,
                    cv,
                    SQLiteDatabase.CONFLICT_REPLACE
                )

                // Update session summary
                val sessCv = ContentValues().apply {
                    put("total_distance_meters", totalDistanceMeters)
                    put("last_accepted_latitude", latitude)
                    put("last_accepted_longitude", longitude)
                    put("last_accepted_time", recordedAt)
                }
                database.update(
                    "offline_sessions",
                    sessCv,
                    "session_uuid = ?",
                    arrayOf(sessionUuid)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error writing GPS point to SQLite: $e")
            }
        }
    }

    private fun pauseTracking() {
        isPaused = true
        locationManager?.removeUpdates(this)
        startForegroundWithNotification("Tracking paused.")
        Log.i(TAG, "Tracking paused")
    }

    private fun resumeTracking() {
        isPaused = false
        startLocationUpdates()
        startForegroundWithNotification("Tracking active.")
        Log.i(TAG, "Tracking resumed")
    }

    private fun stopTrackingSession() {
        Log.i(TAG, "Stopping tracking session")
        isServiceRunning = false
        locationManager?.removeUpdates(this)
        releaseWakeLock()
        try {
            db?.close()
        } catch (_: Exception) {}
        db = null
        stopForeground(true)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val activeUuid = prefs.getString("flutter.active_tracking_session_uuid", null)

        if (activeUuid != null && isServiceRunning) {
            Log.i(TAG, "App swiped from Recents, but session $activeUuid is ACTIVE. Maintaining service.")

            TrackingScheduler.evaluateAndSchedule(applicationContext)

            // Set restart alarm in case system aggressive task killers kill the process
            val restartIntent = Intent(applicationContext, TrackingForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_SESSION_UUID, activeUuid)
            }
            val pIntent = PendingIntent.getService(
                applicationContext,
                1001,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 1000,
                pIntent
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isServiceRunning = false
        locationManager?.removeUpdates(this)
        releaseWakeLock()
        try {
            db?.close()
        } catch (_: Exception) {}
        db = null
        Log.i(TAG, "TrackingForegroundService onDestroy")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onProviderEnabled(provider: String) {
        Log.i(TAG, "Provider enabled: $provider")
        updateNotification(status = "Active", detailText = "Location provider $provider enabled")
        broadcastHealthEvent("GPS_RESTORED", "Location provider $provider enabled")
    }

    override fun onProviderDisabled(provider: String) {
        Log.w(TAG, "Provider disabled: $provider")
        updateNotification(status = "Interrupted", detailText = "Location provider $provider disabled by user")
        broadcastHealthEvent("GPS_DISABLED", "Location provider $provider disabled by user")
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun broadcastHealthEvent(type: String, details: String) {
        val eventMap = mapOf<String, Any?>(
            "event_type" to type,
            "details" to details,
            "timestamp" to formatIsoUtc(Date())
        )
        locationEventListener?.invoke(eventMap)
    }

    private fun haversineDistanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        if (lat1 == lat2 && lon1 == lon2) return 0.0
        val r = 6371000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }

    private fun formatIsoUtc(date: Date): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(date)
    }
}
