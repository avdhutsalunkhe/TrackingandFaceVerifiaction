import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class TrackingDatabase {
  static final TrackingDatabase instance = TrackingDatabase._internal();
  TrackingDatabase._internal();

  Database? _db;

  // In-Memory storage for Web platform
  final List<Map<String, dynamic>> _webOfflineSessions = [];
  final List<Map<String, dynamic>> _webOfflinePoints = [];
  final List<Map<String, dynamic>> _webNotifications = [];
  int _webSessionSeq = 1;
  int _webNotifSeq = 1;
  int _webPointSeq = 1;

  bool isTestMode = false;
  bool get _useMemoryFallback => kIsWeb || isTestMode;

  Future<Database?> get database async {
    if (_useMemoryFallback) return null;
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'fieldstaff_tracking_offline.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        // Table for tracking sessions created offline
        await db.execute("""
          CREATE TABLE offline_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_uuid TEXT NOT NULL UNIQUE,
            user_id INTEGER NOT NULL,
            attendance_id INTEGER,
            shift_id INTEGER,
            work_date TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT,
            status TEXT NOT NULL DEFAULT 'RECORDING',
            start_latitude REAL,
            start_longitude REAL,
            start_accuracy REAL,
            total_distance_meters REAL NOT NULL DEFAULT 0.0,
            total_duration_seconds INTEGER NOT NULL DEFAULT 0,
            sync_status TEXT NOT NULL DEFAULT 'PENDING',
            stop_sync_status TEXT NOT NULL DEFAULT 'NONE'
          )
        """);
        await db.execute('CREATE INDEX idx_offline_sessions_uuid ON offline_sessions (session_uuid)');
        await db.execute('CREATE INDEX idx_offline_sessions_date ON offline_sessions (work_date)');

        // Table for storing recorded GPS points offline
        await db.execute("""
          CREATE TABLE offline_route_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_uuid TEXT NOT NULL,
            client_point_id TEXT NOT NULL UNIQUE,
            sequence_number INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_meters REAL NOT NULL,
            altitude_meters REAL,
            speed_mps REAL,
            bearing_degrees REAL,
            recorded_at TEXT NOT NULL,
            is_gap INTEGER NOT NULL DEFAULT 0,
            sync_status TEXT NOT NULL DEFAULT 'PENDING'
          )
        """);
        await db.execute('CREATE INDEX idx_offline_session ON offline_route_points (session_uuid, sync_status)');
        await db.execute('CREATE INDEX idx_offline_session_seq ON offline_route_points (session_uuid, sequence_number)');

        // Table for in-app notifications history
        await db.execute("""
          CREATE TABLE in_app_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'ATTENDANCE',
            is_read INTEGER NOT NULL DEFAULT 0
          )
        """);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add offline_sessions table if missing
          await db.execute("""
            CREATE TABLE IF NOT EXISTS offline_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_uuid TEXT NOT NULL UNIQUE,
              user_id INTEGER NOT NULL,
              attendance_id INTEGER,
              shift_id INTEGER,
              work_date TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_time TEXT,
              status TEXT NOT NULL DEFAULT 'RECORDING',
              start_latitude REAL,
              start_longitude REAL,
              start_accuracy REAL,
              total_distance_meters REAL NOT NULL DEFAULT 0.0,
              total_duration_seconds INTEGER NOT NULL DEFAULT 0,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              stop_sync_status TEXT NOT NULL DEFAULT 'NONE'
            )
          """);
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_sessions_uuid ON offline_sessions (session_uuid)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_sessions_date ON offline_sessions (work_date)');

          // Add is_gap to offline_route_points if missing
          try {
            await db.execute("ALTER TABLE offline_route_points ADD COLUMN is_gap INTEGER NOT NULL DEFAULT 0");
          } catch (_) {}
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_session_seq ON offline_route_points (session_uuid, sequence_number)');
          } catch (_) {}
        }
      },
    );
  }

  // --- Offline Session Operations ---

  Future<void> queueOfflineSession(Map<String, dynamic> row) async {
    if (_useMemoryFallback) {
      final existingIndex = _webOfflineSessions.indexWhere((s) => s['session_uuid'] == row['session_uuid']);
      final session = Map<String, dynamic>.from(row);
      if (existingIndex >= 0) {
        _webOfflineSessions[existingIndex] = session;
      } else {
        session['id'] = _webSessionSeq++;
        _webOfflineSessions.add(session);
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.insert(
      'offline_sessions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingSessions() async {
    if (_useMemoryFallback) {
      return _webOfflineSessions.where((s) => s['sync_status'] == 'PENDING').toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_sessions',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'start_time ASC',
    );
  }

  Future<void> markSessionSynced(String sessionUuid) async {
    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == sessionUuid) {
          s['sync_status'] = 'SYNCED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update(
      'offline_sessions',
      {'sync_status': 'SYNCED'},
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
    );
  }

  Future<void> queueSessionStop(
    String sessionUuid, {
    double? endLat,
    double? endLng,
    DateTime? endTime,
    double? totalDistanceMeters,
    int? totalDurationSeconds,
  }) async {
    final values = <String, dynamic>{
      'status': 'COMPLETED',
      'stop_sync_status': 'PENDING',
      if (endLat != null) 'end_latitude': endLat,
      if (endLng != null) 'end_longitude': endLng,
      if (endTime != null) 'end_time': endTime.toUtc().toIso8601String(),
      if (totalDistanceMeters != null) 'total_distance_meters': totalDistanceMeters,
      if (totalDurationSeconds != null) 'total_duration_seconds': totalDurationSeconds,
    };

    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == sessionUuid) {
          s.addAll(values);
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update(
      'offline_sessions',
      values,
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingStopSessions() async {
    if (_useMemoryFallback) {
      return _webOfflineSessions.where((s) => s['stop_sync_status'] == 'PENDING').toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_sessions',
      where: 'stop_sync_status = ?',
      whereArgs: ['PENDING'],
    );
  }

  Future<void> markSessionStopSynced(String sessionUuid) async {
    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == sessionUuid) {
          s['stop_sync_status'] = 'SYNCED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update(
      'offline_sessions',
      {'stop_sync_status': 'SYNCED'},
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
    );
  }

  Future<List<Map<String, dynamic>>> getLocalSessionsForDate(String dateStr) async {
    if (_useMemoryFallback) {
      return _webOfflineSessions.where((s) => s['work_date'] == dateStr).toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_sessions',
      where: 'work_date = ?',
      whereArgs: [dateStr],
      orderBy: 'start_time DESC',
    );
  }

  // --- Offline Route Points Operations ---

  Future<int> insertPoint(Map<String, dynamic> row) async {
    if (_useMemoryFallback) {
      final point = Map<String, dynamic>.from(row);
      point['id'] = _webPointSeq++;
      point['sync_status'] = point['sync_status'] ?? 'PENDING';
      point['is_gap'] = point['is_gap'] ?? 0;
      // If client_point_id exists, replace it to avoid duplicate memory keys
      final existingIdx = _webOfflinePoints.indexWhere((p) => p['client_point_id'] == point['client_point_id']);
      if (existingIdx >= 0) {
        _webOfflinePoints[existingIdx] = point;
      } else {
        _webOfflinePoints.add(point);
      }
      return point['id'] as int;
    }
    final db = await database;
    if (db == null) return 0;
    return await db.insert(
      'offline_route_points',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Rekey session UUID across offline sessions and route points when server provides canonical UUID
  Future<void> rekeySessionUuid(String oldSessionUuid, String newSessionUuid) async {
    if (oldSessionUuid == newSessionUuid) return;

    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == oldSessionUuid) {
          s['session_uuid'] = newSessionUuid;
        }
      }
      for (final p in _webOfflinePoints) {
        if (p['session_uuid'] == oldSessionUuid) {
          p['session_uuid'] = newSessionUuid;
          // Also update client_point_id if it starts with the old session uuid
          final String clientPtId = p['client_point_id'] ?? '';
          if (clientPtId.startsWith(oldSessionUuid)) {
            p['client_point_id'] = clientPtId.replaceFirst(oldSessionUuid, newSessionUuid);
          }
        }
      }
      return;
    }

    final db = await database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.update(
        'offline_sessions',
        {'session_uuid': newSessionUuid},
        where: 'session_uuid = ?',
        whereArgs: [oldSessionUuid],
      );
      await txn.update(
        'offline_route_points',
        {'session_uuid': newSessionUuid},
        where: 'session_uuid = ?',
        whereArgs: [oldSessionUuid],
      );
    });
  }

  /// Returns total count of persisted route points for a given session
  Future<int> getPointCount(String sessionUuid) async {
    if (_useMemoryFallback) {
      return _webOfflinePoints.where((p) => p['session_uuid'] == sessionUuid).length;
    }
    final db = await database;
    if (db == null) return 0;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_route_points WHERE session_uuid = ?',
      [sessionUuid],
    );
    if (res.isNotEmpty && res.first['count'] != null) {
      return (res.first['count'] as num).toInt();
    }
    return 0;
  }

  /// Returns the maximum sequence number for the given session to prevent sequence resets and ID collisions.
  Future<int> getMaxSequenceNumber(String sessionUuid) async {
    if (_useMemoryFallback) {
      final points = _webOfflinePoints.where((p) => p['session_uuid'] == sessionUuid);
      if (points.isEmpty) return 0;
      return points.map((p) => (p['sequence_number'] as num).toInt()).reduce(math.max);
    }
    final db = await database;
    if (db == null) return 0;
    final res = await db.rawQuery(
      'SELECT MAX(sequence_number) as max_seq FROM offline_route_points WHERE session_uuid = ?',
      [sessionUuid],
    );
    if (res.isNotEmpty && res.first['max_seq'] != null) {
      return (res.first['max_seq'] as num).toInt();
    }
    return 0;
  }

  /// Returns the most recently accepted GPS point for the session to safely resume distance accounting.
  Future<Map<String, dynamic>?> getLastPoint(String sessionUuid) async {
    if (_useMemoryFallback) {
      final points = _webOfflinePoints.where((p) => p['session_uuid'] == sessionUuid).toList();
      if (points.isEmpty) return null;
      points.sort((a, b) => (b['sequence_number'] as int).compareTo(a['sequence_number'] as int));
      return points.first;
    }
    final db = await database;
    if (db == null) return null;
    final res = await db.query(
      'offline_route_points',
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
      orderBy: 'sequence_number DESC',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Returns all stored points for a session (synced and pending) ordered chronologically for route rendering.
  Future<List<Map<String, dynamic>>> getSessionPoints(String sessionUuid) async {
    if (_useMemoryFallback) {
      return _webOfflinePoints
          .where((p) => p['session_uuid'] == sessionUuid)
          .toList()
        ..sort((a, b) => (a['sequence_number'] as int).compareTo(b['sequence_number'] as int));
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_route_points',
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
      orderBy: 'sequence_number ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingPoints(String sessionUuid) async {
    if (_useMemoryFallback) {
      return _webOfflinePoints
          .where((p) => p['session_uuid'] == sessionUuid && p['sync_status'] == 'PENDING')
          .take(50)
          .toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_route_points',
      where: 'session_uuid = ? AND sync_status = ?',
      whereArgs: [sessionUuid, 'PENDING'],
      orderBy: 'sequence_number ASC',
      limit: 50,
    );
  }

  Future<List<Map<String, dynamic>>> getAllPendingPoints() async {
    if (_useMemoryFallback) {
      return _webOfflinePoints
          .where((p) => p['sync_status'] == 'PENDING')
          .take(100)
          .toList();
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_route_points',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'session_uuid ASC, sequence_number ASC',
      limit: 100,
    );
  }

  Future<void> markPointsSynced(List<String> clientPointIds) async {
    if (clientPointIds.isEmpty) return;
    if (_useMemoryFallback) {
      for (final p in _webOfflinePoints) {
        if (clientPointIds.contains(p['client_point_id'])) {
          p['sync_status'] = 'SYNCED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    final placeholders = List.filled(clientPointIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE offline_route_points SET sync_status = ? WHERE client_point_id IN ($placeholders)',
      ['SYNCED', ...clientPointIds],
    );
  }

  Future<void> markPointsRejected(List<String> clientPointIds) async {
    if (clientPointIds.isEmpty) return;
    if (_useMemoryFallback) {
      for (final p in _webOfflinePoints) {
        if (clientPointIds.contains(p['client_point_id'])) {
          p['sync_status'] = 'REJECTED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    final placeholders = List.filled(clientPointIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE offline_route_points SET sync_status = ? WHERE client_point_id IN ($placeholders)',
      ['REJECTED', ...clientPointIds],
    );
  }

  // --- In-App Notification Operations ---

  Future<int> insertNotification(String title, String message, {String category = 'ATTENDANCE'}) async {
    if (_useMemoryFallback) {
      final id = _webNotifSeq++;
      _webNotifications.insert(0, {
        'id': id,
        'title': title,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
        'category': category,
        'is_read': 0,
      });
      return id;
    }
    final db = await database;
    if (db == null) return 0;
    return await db.insert('in_app_notifications', {
      'title': title,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      'category': category,
      'is_read': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    if (_useMemoryFallback) {
      return List<Map<String, dynamic>>.from(_webNotifications);
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'in_app_notifications',
      orderBy: 'id DESC',
    );
  }

  Future<void> markNotificationRead(int id) async {
    if (_useMemoryFallback) {
      for (final n in _webNotifications) {
        if (n['id'] == id) n['is_read'] = 1;
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update('in_app_notifications', {'is_read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAllNotificationsRead() async {
    if (_useMemoryFallback) {
      for (final n in _webNotifications) {
        n['is_read'] = 1;
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update('in_app_notifications', {'is_read': 1});
  }

  Future<void> clearAllNotifications() async {
    if (_useMemoryFallback) {
      _webNotifications.clear();
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.delete('in_app_notifications');
  }

  Future<int> getUnreadNotificationCount() async {
    if (_useMemoryFallback) {
      return _webNotifications.where((n) => (n['is_read'] ?? 0) == 0).length;
    }
    final db = await database;
    if (db == null) return 0;
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM in_app_notifications WHERE is_read = 0');
    return Sqflite.firstIntValue(res) ?? 0;
  }
}
