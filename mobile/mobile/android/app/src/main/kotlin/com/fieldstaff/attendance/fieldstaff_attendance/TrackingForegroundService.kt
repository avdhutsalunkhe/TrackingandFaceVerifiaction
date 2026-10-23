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
import android.content.pm.PackageManager
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
import androidx.core.content.ContextCompat
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import org.json.JSONArray
import org.json.JSONObject

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

    private val kalmanFilter = AndroidKalmanLatLongFilter(qMetersPerSecond = 3.0)

    private var isPaused: Boolean = false
    private var db: SQLiteDatabase? = null
    private val networkExecutor = Executors.newSingleThreadExecutor()
    @Volatile
    private var isBacklogSyncInProgress = false

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
                // Must call startForeground immediately to fulfill Android foreground service contract
                startForegroundWithNotification("Tracking started. Acquiring GPS fixes...")

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

                // Request location updates
                startLocationUpdates()
                isServiceRunning = true
            }
        }

        // Return START_STICKY to allow Android process recreation after memory pressure
        return START_STICKY
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FieldTrack Duty Tracking",
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
        } ?: Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val statusLine = when (status) {
            "Active" -> "Field Duty Tracking Active"
            "Interrupted" -> detailText ?: "Field Duty Tracking Interrupted"
            "Paused" -> "Field Duty Tracking Paused"
            else -> detailText ?: "Field Duty Tracking"
        }

        val accuracyStr = if (accuracyMeters != null) " (±${accuracyMeters.toInt()}m)" else ""
        val formattedDist = String.format(Locale.US, "%.2f", distKm)
        val bigText = "$statusLine\nSchedule: $scheduleDisplay\nLast GPS update: $lastFixStr$accuracyStr\nTotal Travel: $formattedDist km"

        val iconRes = try {
            val resId = resources.getIdentifier("ic_stat_fieldtrack", "drawable", packageName)
            if (resId != 0) resId else applicationInfo.icon
        } catch (_: Exception) {
            applicationInfo.icon
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FieldTrack")
            .setContentText("$statusLine • Schedule: $scheduleDisplay")
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setSmallIcon(iconRes)
            .setOngoing(status == "Active" || status == "Interrupted")
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun startForegroundWithNotification(contentText: String) {
        try {
            val notification = buildNotification(status = "Active", detailText = contentText)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (hasLocationPermission()) {
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Android 14: Use dataSync foreground type when location permission is pending
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForegroundWithNotification primary failed: $e")
            try {
                val notification = buildNotification(status = "Active", detailText = contentText)
                startForeground(NOTIFICATION_ID, notification)
            } catch (e2: Exception) {
                Log.e(TAG, "startForegroundWithNotification fatal fallback failed: $e2")
            }
        }
    }

    private fun updateNotification(status: String = "Active", detailText: String? = null, accuracyMeters: Float? = null) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notification = buildNotification(status, detailText, accuracyMeters)
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Could not update notification: $e")
        }
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
                // Query max sequence number from SQLite and SharedPreferences
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val prefSeq = prefs.getInt("tracking_last_seq_$sUuid", 0)
                var maxSeq = prefSeq

                val cursor = database.rawQuery(
                    "SELECT MAX(sequence_number) FROM offline_route_points WHERE session_uuid = ?",
                    arrayOf(sUuid)
                )
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    val dbMaxSeq = cursor.getInt(0)
                    if (dbMaxSeq > maxSeq) {
                        maxSeq = dbMaxSeq
                    }
                }
                cursor.close()

                if (maxSeq > 0) {
                    sequenceNumber = maxSeq + 1
                }

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
                kalmanFilter.reset(lastLat, lastLng, 10.0, System.currentTimeMillis())
                Log.i(TAG, "State restored for $sUuid: seq=$sequenceNumber, dist=${totalDistanceMeters}m, lastPos=($lastLat, $lastLng)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore state from SQLite: $e")
        }
    }

    private fun startLocationUpdates() {
        if (!hasLocationPermission()) {
            Log.w(TAG, "Location permission not yet granted by user; deferring updates")
            broadcastHealthEvent("PERMISSION_DENIED", "Location permission pending user grant")
            return
        }
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

        val rawLat = loc.latitude
        val rawLng = loc.longitude
        val rawAccuracy = loc.accuracy

        // Stage 1: Boundary & Sentinel Check (NaN, Infinite, out-of-bounds, Null Island)
        if (rawLat < -90.0 || rawLat > 90.0 || rawLng < -180.0 || rawLng > 180.0) return
        if (Math.abs(rawLat) < 1e-6 && Math.abs(rawLng) < 1e-6) return

        // Stage 2: Accuracy Threshold Gate (discard fixes > 65m)
        if (rawAccuracy > 65.0f) {
            Log.d(TAG, "Fix dropped due to poor accuracy: ${rawAccuracy}m > 65m")
            return
        }

        val nowMs = System.currentTimeMillis()
        val sUuid = sessionUuid!!

        // 2D Kalman Filtering: balance previous state against incoming GPS measurement
        val filtered = kalmanFilter.process(rawLat, rawLng, rawAccuracy.toDouble(), nowMs)
        val lat = filtered.latitude
        val lng = filtered.longitude
        val accuracy = filtered.accuracy.toFloat()

        val elapsedSec = if (lastFixTimeMs > 0L) (nowMs - lastFixTimeMs) / 1000.0 else 0.0

        // Stage 3: Discontinuous Gap Detection (> 15 minutes = 900s)
        val isGap = elapsedSec > 900.0
        if (isGap) {
            lastLat = lat
            lastLng = lng
            lastFixTimeMs = nowMs
        }

        // Calculate step displacement
        var stepDist = 0.0
        if (!isGap && lastLat != null && lastLng != null) {
            stepDist = haversineDistanceMeters(lastLat!!, lastLng!!, lat, lng)

            // Stage 4: Teleportation & Glitch Detection (Implied speed > 55 m/s ≈ 198 km/h)
            if (elapsedSec > 0.5 && stepDist > 40.0) {
                val speed = stepDist / elapsedSec
                if (speed > 55.0) {
                    Log.w(TAG, "Implied speed excessive (${speed}m/s > 55m/s), dropping jump")
                    return
                }
            }
        }

        // Stage 5: Stationary Drift Suppression (Dead-Reckoning Threshold)
        // Speeds < 0.4 m/s with displacement < 4.0m are filtered out to prevent stationary drift
        val isStationary = loc.hasSpeed() && loc.speed < 0.4f && stepDist < 4.0
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!isStationary && stepDist >= 8.0) {
            totalDistanceMeters += stepDist
            lastLat = lat
            lastLng = lng
            lastFixTimeMs = nowMs

            // Update SharedPreferences for Flutter
            prefs.edit().putFloat("flutter.active_tracking_distance", totalDistanceMeters.toFloat()).apply()
        } else if (lastLat == null) {
            lastLat = lat
            lastLng = lng
            lastFixTimeMs = nowMs
        }

        val seq = sequenceNumber++
        prefs.edit().putInt("tracking_last_seq_$sUuid", seq).apply()
        val clientPointId = "${sUuid}_pt_${seq}_${nowMs}"
        val isoTimestamp = formatIsoUtc(Date(loc.time))

        // Direct real-time upload when online; fallback to SQLite only on failure
        uploadOrBufferPoint(
            sessionUuid = sUuid,
            clientPointId = clientPointId,
            sequenceNumber = seq,
            latitude = lat,
            longitude = lng,
            accuracy = accuracy.toDouble(),
            altitude = loc.altitude,
            speed = if (loc.hasSpeed()) loc.speed.toDouble() else null,
            bearing = if (loc.hasBearing()) loc.bearing.toDouble() else null,
            recordedAt = isoTimestamp,
            totalDistanceMeters = totalDistanceMeters
        )
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

    private fun uploadOrBufferPoint(
        sessionUuid: String,
        clientPointId: String,
        sequenceNumber: Int,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        altitude: Double?,
        speed: Double?,
        bearing: Double?,
        recordedAt: String,
        totalDistanceMeters: Double
    ) {
        networkExecutor.execute {
            var isDirectlyUploaded = false
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val token = prefs.getString("flutter.access_token", null)
                val activeServer = prefs.getString("flutter.active_api_url", null)
                    ?: prefs.getString("flutter.custom_base_url", null)
                    ?: "http://182.66.233.66:8084"

                val ptObj = JSONObject().apply {
                    put("client_point_id", clientPointId)
                    put("sequence_number", sequenceNumber)
                    put("latitude", latitude)
                    put("longitude", longitude)
                    put("accuracy_meters", accuracy)
                    if (altitude != null) put("altitude_meters", altitude)
                    if (speed != null) put("speed_mps", speed)
                    if (bearing != null) put("bearing_degrees", bearing)
                    put("recorded_at", recordedAt)
                    put("is_gap", false)
                }
                val pointsArray = JSONArray().apply { put(ptObj) }
                val rootObj = JSONObject().apply {
                    put("session_uuid", sessionUuid)
                    put("points", pointsArray)
                    put("current_distance_meters", totalDistanceMeters)
                }

                val candidateUrls = listOfNotNull(
                    activeServer,
                    if (activeServer != "http://182.66.233.66:8084") "http://182.66.233.66:8084" else null,
                    if (activeServer != "http://115.244.240.22:8084") "http://115.244.240.22:8084" else null,
                    if (activeServer != "http://192.168.1.91:8084") "http://192.168.1.91:8084" else null
                )

                for (baseUrl in candidateUrls) {
                    try {
                        val endpoint = URL("$baseUrl/api/tracking/points")
                        val conn = (endpoint.openConnection() as HttpURLConnection).apply {
                            requestMethod = "POST"
                            setRequestProperty("Content-Type", "application/json; charset=utf-8")
                            setRequestProperty("Accept", "application/json")
                            if (!token.isNullOrEmpty()) {
                                setRequestProperty("Authorization", "Bearer $token")
                            }
                            connectTimeout = 4000
                            readTimeout = 5000
                            doOutput = true
                            doInput = true
                        }

                        OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                            writer.write(rootObj.toString())
                            writer.flush()
                        }

                        val responseCode = conn.responseCode
                        if (responseCode in 200..299) {
                            val respText = conn.inputStream.bufferedReader().use { it.readText() }
                            val respJson = JSONObject(respText)
                            if (respJson.optBoolean("success", true)) {
                                isDirectlyUploaded = true
                                Log.i(TAG, "Point $clientPointId uploaded DIRECTLY online to $baseUrl (HTTP $responseCode)")
                                prefs.edit().putString("flutter.active_api_url", baseUrl).apply()
                                break
                            }
                        } else if (responseCode == 403) {
                            Log.w(TAG, "Backend rejected tracking point with HTTP 403. Stop capturing.")
                            break
                        }
                    } catch (e: Exception) {
                        Log.d(TAG, "Direct upload to $baseUrl failed: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error in direct upload attempt: $e")
            }

            if (isDirectlyUploaded) {
                // Online success: Do NOT write coordinates to offline_route_points!
                updateSessionSummary(sessionUuid, latitude, longitude, recordedAt, totalDistanceMeters)
                updateNotification(status = "Active (Live)", accuracyMeters = accuracy.toFloat())

                val pointMap = mapOf<String, Any?>(
                    "session_uuid" to sessionUuid,
                    "client_point_id" to clientPointId,
                    "sequence_number" to sequenceNumber,
                    "latitude" to latitude,
                    "longitude" to longitude,
                    "accuracy_meters" to accuracy,
                    "altitude_meters" to altitude,
                    "speed_mps" to speed,
                    "bearing_degrees" to bearing,
                    "recorded_at" to recordedAt,
                    "total_distance_meters" to totalDistanceMeters,
                    "sync_status" to "SYNCED"
                )
                locationEventListener?.invoke(pointMap)

                // Check and trigger backlog sync if offline points were previously buffered
                syncBacklogPointsAsync(sessionUuid)
            } else {
                // Offline fallback: Delivery failed, persist to SQLite with PENDING status
                Log.w(TAG, "Direct upload failed/offline: Buffering point $clientPointId to offline_route_points")
                persistPointToDb(
                    sessionUuid = sessionUuid,
                    clientPointId = clientPointId,
                    sequenceNumber = sequenceNumber,
                    latitude = latitude,
                    longitude = longitude,
                    accuracy = accuracy,
                    altitude = altitude,
                    speed = speed,
                    bearing = bearing,
                    recordedAt = recordedAt
                )
                updateNotification(status = "Active (Offline Buffer)", accuracyMeters = accuracy.toFloat())

                val pointMap = mapOf<String, Any?>(
                    "session_uuid" to sessionUuid,
                    "client_point_id" to clientPointId,
                    "sequence_number" to sequenceNumber,
                    "latitude" to latitude,
                    "longitude" to longitude,
                    "accuracy_meters" to accuracy,
                    "altitude_meters" to altitude,
                    "speed_mps" to speed,
                    "bearing_degrees" to bearing,
                    "recorded_at" to recordedAt,
                    "total_distance_meters" to totalDistanceMeters,
                    "sync_status" to "PENDING"
                )
                locationEventListener?.invoke(pointMap)
            }
        }
    }

    private fun updateSessionSummary(
        sessionUuid: String,
        latitude: Double,
        longitude: Double,
        recordedAt: String,
        totalDistanceMeters: Double
    ) {
        if (db == null || !db!!.isOpen) {
            initDatabase()
        }
        db?.let { database ->
            try {
                val cv = ContentValues().apply {
                    put("total_distance_meters", totalDistanceMeters)
                    put("last_accepted_latitude", latitude)
                    put("last_accepted_longitude", longitude)
                    put("last_accepted_time", recordedAt)
                }
                database.update(
                    "offline_sessions",
                    cv,
                    "session_uuid = ?",
                    arrayOf(sessionUuid)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error updating session summary: $e")
            }
        }
    }

    private fun syncBacklogPointsAsync(sessionUuid: String) {
        if (isBacklogSyncInProgress) return
        networkExecutor.execute {
            if (isBacklogSyncInProgress) return@execute
            isBacklogSyncInProgress = true
            try {
                if (db == null || !db!!.isOpen) initDatabase()
                val database = db ?: return@execute

                val cursor = database.rawQuery(
                    "SELECT client_point_id, sequence_number, latitude, longitude, accuracy_meters, altitude_meters, speed_mps, bearing_degrees, recorded_at " +
                    "FROM offline_route_points WHERE session_uuid = ? AND sync_status = 'PENDING' ORDER BY sequence_number ASC LIMIT 100",
                    arrayOf(sessionUuid)
                )

                val pointsList = mutableListOf<JSONObject>()
                val clientIds = mutableListOf<String>()

                while (cursor.moveToNext()) {
                    val cId = cursor.getString(0)
                    val seq = cursor.getInt(1)
                    val lat = cursor.getDouble(2)
                    val lng = cursor.getDouble(3)
                    val acc = cursor.getDouble(4)
                    val alt = if (cursor.isNull(5)) null else cursor.getDouble(5)
                    val spd = if (cursor.isNull(6)) null else cursor.getDouble(6)
                    val brg = if (cursor.isNull(7)) null else cursor.getDouble(7)
                    val recAt = cursor.getString(8)

                    clientIds.add(cId)
                    val pObj = JSONObject().apply {
                        put("client_point_id", cId)
                        put("sequence_number", seq)
                        put("latitude", lat)
                        put("longitude", lng)
                        put("accuracy_meters", acc)
                        if (alt != null) put("altitude_meters", alt)
                        if (spd != null) put("speed_mps", spd)
                        if (brg != null) put("bearing_degrees", brg)
                        put("recorded_at", recAt)
                        put("is_gap", false)
                    }
                    pointsList.add(pObj)
                }
                cursor.close()

                if (pointsList.isEmpty()) {
                    isBacklogSyncInProgress = false
                    return@execute
                }

                Log.i(TAG, "Syncing ${pointsList.size} backlog points for session $sessionUuid...")
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val token = prefs.getString("flutter.access_token", null)
                val baseUrl = prefs.getString("flutter.active_api_url", null) ?: "http://182.66.233.66:8084"

                val payload = JSONObject().apply {
                    put("session_uuid", sessionUuid)
                    val arr = JSONArray()
                    pointsList.forEach { arr.put(it) }
                    put("points", arr)
                    put("current_distance_meters", totalDistanceMeters)
                }

                val conn = (URL("$baseUrl/api/tracking/points").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    setRequestProperty("Accept", "application/json")
                    if (!token.isNullOrEmpty()) {
                        setRequestProperty("Authorization", "Bearer $token")
                    }
                    connectTimeout = 6000
                    readTimeout = 10000
                    doOutput = true
                    doInput = true
                }

                OutputStreamWriter(conn.outputStream, "UTF-8").use {
                    it.write(payload.toString())
                    it.flush()
                }

                if (conn.responseCode in 200..299) {
                    val respText = conn.inputStream.bufferedReader().use { it.readText() }
                    val respJson = JSONObject(respText)
                    val confirmedIds = mutableListOf<String>()
                    val syncedArr = respJson.optJSONArray("synced_point_ids")
                    if (syncedArr != null && syncedArr.length() > 0) {
                        for (i in 0 until syncedArr.length()) {
                            confirmedIds.add(syncedArr.getString(i))
                        }
                    } else {
                        confirmedIds.addAll(clientIds)
                    }

                    // Delete confirmed backlog points from SQLite in chunks of 500
                    database.beginTransaction()
                    try {
                        for (chunk in confirmedIds.chunked(500)) {
                            val placeholders = chunk.joinToString(",") { "?" }
                            database.delete("offline_route_points", "client_point_id IN ($placeholders)", chunk.toTypedArray())
                        }
                        database.setTransactionSuccessful()
                    } finally {
                        database.endTransaction()
                    }
                    Log.i(TAG, "Successfully synced and purged ${confirmedIds.size} backlog points from SQLite.")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Backlog synchronization deferred: $e")
            } finally {
                isBacklogSyncInProgress = false
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

            // Set restart alarm via TrackingBootReceiver to comply with Android 12+ foreground service launch rules
            val restartIntent = Intent(applicationContext, TrackingBootReceiver::class.java).apply {
                action = TrackingScheduler.ACTION_WATCHDOG
            }
            val pIntent = PendingIntent.getBroadcast(
                applicationContext,
                1004,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1500,
                    pIntent
                )
            } else {
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1500,
                    pIntent
                )
            }
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
        try {
            networkExecutor.shutdown()
        } catch (_: Exception) {}
        Log.i(TAG, "TrackingForegroundService onDestroy")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onProviderEnabled(provider: String) {
        Log.i(TAG, "Provider enabled: $provider")
        updateNotification(status = "Active", detailText = "Location provider $provider enabled")
        closeInterruptionInDb("LOCATION_SERVICES_DISABLED")
        broadcastHealthEvent("GPS_RESTORED", "Location provider $provider enabled")
    }

    override fun onProviderDisabled(provider: String) {
        Log.w(TAG, "Provider disabled: $provider")
        updateNotification(status = "Interrupted", detailText = "Location provider $provider disabled by user")
        recordInterruptionToDb("LOCATION_SERVICES_DISABLED", "Location provider $provider disabled by user", "WARNING")
        broadcastHealthEvent("GPS_DISABLED", "Location provider $provider disabled by user")
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun recordInterruptionToDb(reasonCode: String, description: String, severity: String = "WARNING") {
        val sUuid = sessionUuid ?: return
        val nowMs = System.currentTimeMillis()
        val isoNow = formatIsoUtc(Date(nowMs))
        val eventUuid = "EV_${reasonCode}_${sUuid}_${nowMs}"

        if (db == null || !db!!.isOpen) {
            initDatabase()
        }
        db?.let { database ->
            try {
                val cv = ContentValues().apply {
                    put("event_uuid", eventUuid)
                    put("session_uuid", sUuid)
                    put("user_id", userId)
                    put("reason_code", reasonCode)
                    put("description", description)
                    put("severity", severity)
                    put("detected_at", isoNow)
                    if (lastLat != null) put("last_known_latitude", lastLat)
                    if (lastLng != null) put("last_known_longitude", lastLng)
                    if (lastFixTimeMs > 0) put("last_known_location_time", formatIsoUtc(Date(lastFixTimeMs)))
                    put("is_confirmed", 1)
                    put("recovery_outcome", "UNRESOLVED")
                    put("sync_status", "PENDING")
                }
                database.insertWithOnConflict("offline_interruption_events", null, cv, SQLiteDatabase.CONFLICT_REPLACE)

                val sessCv = ContentValues().apply {
                    put("status", "INTERRUPTED")
                }
                database.update("offline_sessions", sessCv, "session_uuid = ?", arrayOf(sUuid))
            } catch (e: Exception) {
                Log.e(TAG, "Error writing interruption event to SQLite: $e")
            }
        }
    }

    private fun closeInterruptionInDb(reasonCode: String) {
        val sUuid = sessionUuid ?: return
        val nowMs = System.currentTimeMillis()
        val isoNow = formatIsoUtc(Date(nowMs))

        if (db == null || !db!!.isOpen) {
            initDatabase()
        }
        db?.let { database ->
            try {
                val cursor = database.rawQuery(
                    "SELECT event_uuid, detected_at FROM offline_interruption_events WHERE session_uuid = ? AND reason_code = ? AND recovery_outcome = 'UNRESOLVED' ORDER BY detected_at DESC LIMIT 1",
                    arrayOf(sUuid, reasonCode)
                )
                if (cursor.moveToFirst()) {
                    val evUuid = cursor.getString(0)
                    val detectedStr = cursor.getString(1)
                    var durationSec = 0
                    try {
                        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                            timeZone = TimeZone.getTimeZone("UTC")
                        }
                        val dDate = sdf.parse(detectedStr)
                        if (dDate != null) {
                            durationSec = Math.max(0, ((nowMs - dDate.time) / 1000).toInt())
                        }
                    } catch (_: Exception) {}

                    val cv = ContentValues().apply {
                        put("recovered_at", isoNow)
                        put("duration_seconds", durationSec)
                        put("recovery_outcome", "RECOVERED")
                        put("sync_status", "PENDING")
                    }
                    database.update("offline_interruption_events", cv, "event_uuid = ?", arrayOf(evUuid))
                }
                cursor.close()

                val sessCv = ContentValues().apply {
                    put("status", "RECORDING")
                }
                database.update("offline_sessions", sessCv, "session_uuid = ?", arrayOf(sUuid))
            } catch (e: Exception) {
                Log.e(TAG, "Error closing interruption event in SQLite: $e")
            }
        }
    }

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

/**
 * 2D Kalman Filter for Android native location stream.
 * Maintains full 64-bit double precision, with process noise Q = 3.0 m/s and dynamic R = accuracy^2.
 */
class AndroidKalmanLatLongFilter(private val qMetersPerSecond: Double = 3.0) {
    private var lat: Double? = null
    private var lng: Double? = null
    private var variance: Double = -1.0
    private var timestampMs: Long = 0L

    fun reset(initialLat: Double? = null, initialLng: Double? = null, accuracy: Double? = null, tsMs: Long? = null) {
        lat = initialLat
        lng = initialLng
        variance = if (accuracy != null && accuracy > 0) accuracy * accuracy else -1.0
        timestampMs = tsMs ?: 0L
    }

    data class FilterResult(val latitude: Double, val longitude: Double, val accuracy: Double)

    fun process(rawLat: Double, rawLng: Double, rawAccuracy: Double, tsMs: Long): FilterResult {
        val safeAccuracy = if (rawAccuracy < 1.0) 1.0 else rawAccuracy
        if (variance < 0 || lat == null || lng == null) {
            lat = rawLat
            lng = rawLng
            variance = safeAccuracy * safeAccuracy
            timestampMs = tsMs
        } else {
            val dtSeconds = Math.max(0.0, (tsMs - timestampMs) / 1000.0)
            if (dtSeconds > 0) {
                variance += dtSeconds * qMetersPerSecond * qMetersPerSecond
                timestampMs = tsMs
            }
            val measurementVariance = safeAccuracy * safeAccuracy
            val kalmanGain = variance / (variance + measurementVariance)
            lat = lat!! + kalmanGain * (rawLat - lat!!)
            lng = lng!! + kalmanGain * (rawLng - lng!!)
            variance = (1.0 - kalmanGain) * variance
        }
        return FilterResult(lat!!, lng!!, Math.sqrt(variance))
    }
}
