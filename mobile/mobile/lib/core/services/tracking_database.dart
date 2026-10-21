import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class TrackingDatabase {
  static final TrackingDatabase instance = TrackingDatabase._internal();
  TrackingDatabase._internal();

  Database? _db;

  // In-Memory storage for Web platform & testing
  final List<Map<String, dynamic>> _webOfflineSessions = [];
  final List<Map<String, dynamic>> _webOfflinePoints = [];
  final List<Map<String, dynamic>> _webOfflineChunks = [];
  final List<Map<String, dynamic>> _webOfflineInterruptionEvents = [];
  final List<Map<String, dynamic>> _webNotifications = [];
  int _webSessionSeq = 1;
  int _webNotifSeq = 1;
  int _webPointSeq = 1;
  int _webChunkSeq = 1;
  int _webEventSeq = 1;

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
      version: 4,
      onCreate: (db, version) async {
        // Table for tracking sessions created offline (1 summary row per session)
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
            end_latitude REAL,
            end_longitude REAL,
            total_distance_meters REAL NOT NULL DEFAULT 0.0,
            total_duration_seconds INTEGER NOT NULL DEFAULT 0,
            retained_point_count INTEGER NOT NULL DEFAULT 0,
            last_accepted_latitude REAL,
            last_accepted_longitude REAL,
            last_accepted_time TEXT,
            sync_status TEXT NOT NULL DEFAULT 'PENDING',
            stop_sync_status TEXT NOT NULL DEFAULT 'NONE'
          )
        """);
        await db.execute('CREATE INDEX idx_offline_sessions_uuid ON offline_sessions (session_uuid)');
        await db.execute('CREATE INDEX idx_offline_sessions_date ON offline_sessions (work_date)');

        // Production Storage-Efficient Table: stores compressed route chunks (retained vertices)
        await db.execute("""
          CREATE TABLE offline_route_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chunk_uuid TEXT NOT NULL UNIQUE,
            session_uuid TEXT NOT NULL,
            chunk_sequence INTEGER NOT NULL,
            point_count INTEGER NOT NULL DEFAULT 0,
            encoded_geometry TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            distance_meters REAL NOT NULL DEFAULT 0.0,
            sync_status TEXT NOT NULL DEFAULT 'PENDING'
          )
        """);
        await db.execute('CREATE INDEX idx_offline_chunks_session ON offline_route_chunks (session_uuid, chunk_sequence)');
        await db.execute('CREATE INDEX idx_offline_chunks_sync ON offline_route_chunks (sync_status)');

        // Legacy table for backward-compatible individual route points
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

        // Table for durable tracking interruption events
        await db.execute("""
          CREATE TABLE offline_interruption_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_uuid TEXT NOT NULL UNIQUE,
            session_uuid TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            device_id TEXT,
            reason_code TEXT NOT NULL,
            description TEXT NOT NULL,
            severity TEXT NOT NULL DEFAULT 'WARNING',
            detected_at TEXT NOT NULL,
            recovered_at TEXT,
            duration_seconds INTEGER,
            last_known_latitude REAL,
            last_known_longitude REAL,
            last_known_location_time TEXT,
            diagnostic_details TEXT,
            is_confirmed INTEGER NOT NULL DEFAULT 1,
            recovery_outcome TEXT NOT NULL DEFAULT 'UNRESOLVED',
            sync_status TEXT NOT NULL DEFAULT 'PENDING'
          )
        """);
        await db.execute('CREATE INDEX idx_offline_events_session ON offline_interruption_events (session_uuid, detected_at)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
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

          try {
            await db.execute("ALTER TABLE offline_route_points ADD COLUMN is_gap INTEGER NOT NULL DEFAULT 0");
          } catch (_) {}
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_session_seq ON offline_route_points (session_uuid, sequence_number)');
          } catch (_) {}
        }

        if (oldVersion < 3) {
          // Version 3: Storage-Efficient Compressed Route Chunks Table
          await db.execute("""
            CREATE TABLE IF NOT EXISTS offline_route_chunks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              chunk_uuid TEXT NOT NULL UNIQUE,
              session_uuid TEXT NOT NULL,
              chunk_sequence INTEGER NOT NULL,
              point_count INTEGER NOT NULL DEFAULT 0,
              encoded_geometry TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_time TEXT NOT NULL,
              distance_meters REAL NOT NULL DEFAULT 0.0,
              sync_status TEXT NOT NULL DEFAULT 'PENDING'
            )
          """);
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_chunks_session ON offline_route_chunks (session_uuid, chunk_sequence)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_chunks_sync ON offline_route_chunks (sync_status)');

          // Safe column additions for session summary enhancements
          try {
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN retained_point_count INTEGER NOT NULL DEFAULT 0");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN end_latitude REAL");
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN end_longitude REAL");
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN last_accepted_latitude REAL");
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN last_accepted_longitude REAL");
            await db.execute("ALTER TABLE offline_sessions ADD COLUMN last_accepted_time TEXT");
          } catch (_) {}
        }

        if (oldVersion < 4) {
          // Version 4: Durable Interruption Events Table
          await db.execute("""
            CREATE TABLE IF NOT EXISTS offline_interruption_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              event_uuid TEXT NOT NULL UNIQUE,
              session_uuid TEXT NOT NULL,
              user_id INTEGER NOT NULL,
              device_id TEXT,
              reason_code TEXT NOT NULL,
              description TEXT NOT NULL,
              severity TEXT NOT NULL DEFAULT 'WARNING',
              detected_at TEXT NOT NULL,
              recovered_at TEXT,
              duration_seconds INTEGER,
              last_known_latitude REAL,
              last_known_longitude REAL,
              last_known_location_time TEXT,
              diagnostic_details TEXT,
              is_confirmed INTEGER NOT NULL DEFAULT 1,
              recovery_outcome TEXT NOT NULL DEFAULT 'UNRESOLVED',
              sync_status TEXT NOT NULL DEFAULT 'PENDING'
            )
          """);
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_events_session ON offline_interruption_events (session_uuid, detected_at)');
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

  Future<int> queueOfflinePoint(Map<String, dynamic> row) => insertPoint(row);

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

  /// In-place updates to session summary record (distance, duration, retained point count, last fix)
  Future<void> updateSessionSummary(String sessionUuid, Map<String, dynamic> updates) async {
    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == sessionUuid) {
          s.addAll(updates);
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.update(
      'offline_sessions',
      updates,
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
    );
  }

  // --- Production Compressed Route Chunks Operations ---

  /// Persists an incrementally encoded route chunk containing retained vertices
  Future<int> insertRouteChunk(Map<String, dynamic> row) async {
    if (_useMemoryFallback) {
      final chunk = Map<String, dynamic>.from(row);
      chunk['id'] = _webChunkSeq++;
      chunk['sync_status'] = chunk['sync_status'] ?? 'PENDING';
      final existingIdx = _webOfflineChunks.indexWhere((c) => c['chunk_uuid'] == chunk['chunk_uuid']);
      if (existingIdx >= 0) {
        _webOfflineChunks[existingIdx] = chunk;
      } else {
        _webOfflineChunks.add(chunk);
      }
      return chunk['id'] as int;
    }
    final db = await database;
    if (db == null) return 0;
    return await db.insert(
      'offline_route_chunks',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns highest chunk sequence for this session to prevent sequence collisions
  Future<int> getMaxChunkSequence(String sessionUuid) async {
    if (_useMemoryFallback) {
      final chunks = _webOfflineChunks.where((c) => c['session_uuid'] == sessionUuid);
      if (chunks.isEmpty) return 0;
      return chunks.map((c) => (c['chunk_sequence'] as num).toInt()).reduce(math.max);
    }
    final db = await database;
    if (db == null) return 0;
    final res = await db.rawQuery(
      'SELECT MAX(chunk_sequence) as max_seq FROM offline_route_chunks WHERE session_uuid = ?',
      [sessionUuid],
    );
    if (res.isNotEmpty && res.first['max_seq'] != null) {
      return (res.first['max_seq'] as num).toInt();
    }
    return 0;
  }

  /// Retrieves pending route chunks for cloud upload
  Future<List<Map<String, dynamic>>> getPendingRouteChunks([String? sessionUuid]) async {
    if (_useMemoryFallback) {
      return _webOfflineChunks
          .where((c) => c['sync_status'] == 'PENDING' && (sessionUuid == null || c['session_uuid'] == sessionUuid))
          .take(20)
          .toList();
    }
    final db = await database;
    if (db == null) return [];
    final whereClause = sessionUuid != null ? 'sync_status = ? AND session_uuid = ?' : 'sync_status = ?';
    final whereArgs = sessionUuid != null ? ['PENDING', sessionUuid] : ['PENDING'];

    return await db.query(
      'offline_route_chunks',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'session_uuid ASC, chunk_sequence ASC',
      limit: 20,
    );
  }

  /// Marks a batch of chunk UUIDs as successfully synchronized
  Future<void> markChunksSynced(List<String> chunkUuids) async {
    if (chunkUuids.isEmpty) return;
    if (_useMemoryFallback) {
      for (final c in _webOfflineChunks) {
        if (chunkUuids.contains(c['chunk_uuid'])) {
          c['sync_status'] = 'SYNCED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    final placeholders = List.filled(chunkUuids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE offline_route_chunks SET sync_status = ? WHERE chunk_uuid IN ($placeholders)',
      ['SYNCED', ...chunkUuids],
    );
  }

  /// Retrieves all route chunks for a session ordered chronologically
  Future<List<Map<String, dynamic>>> getSessionRouteChunks(String sessionUuid) async {
    if (_useMemoryFallback) {
      return _webOfflineChunks
          .where((c) => c['session_uuid'] == sessionUuid)
          .toList()
        ..sort((a, b) => (a['chunk_sequence'] as int).compareTo(b['chunk_sequence'] as int));
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_route_chunks',
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
      orderBy: 'chunk_sequence ASC',
    );
  }

  /// Decodes and reconstructs chronological route vertices from compressed chunks for map rendering.
  /// Returns all session points. Prioritizes raw GPS observations from offline_route_points.
  /// Falls back to storage-efficient chunks only if raw points table is empty.
  Future<List<Map<String, dynamic>>> getSessionReconstructedPoints(String sessionUuid) async {
    // 1. Raw GPS points are authoritative
    final rawPoints = await getSessionPoints(sessionUuid);
    if (rawPoints.isNotEmpty) {
      return rawPoints;
    }

    // 2. Fallback to storage-efficient chunks if raw points table has no records
    final chunks = await getSessionRouteChunks(sessionUuid);
    if (chunks.isNotEmpty) {
      final List<Map<String, dynamic>> reconstructed = [];
      int seqCounter = 1;

      for (final chunk in chunks) {
        final geomStr = chunk['encoded_geometry'] as String;
        try {
          final decoded = jsonDecode(geomStr) as List;
          for (final item in decoded) {
            final lat = (item[0] as num).toDouble();
            final lng = (item[1] as num).toDouble();
            final epochSec = (item[2] as num).toInt();
            final acc = (item[3] as num).toDouble();
            final spd = item.length > 4 && item[4] != null ? (item[4] as num).toDouble() : null;
            final brg = item.length > 5 && item[5] != null ? (item[5] as num).toDouble() : null;
            final isGap = item.length > 6 ? (item[6] == 1 || item[6] == true) : false;

            reconstructed.add({
              'session_uuid': sessionUuid,
              'sequence_number': seqCounter++,
              'latitude': lat,
              'longitude': lng,
              'accuracy_meters': acc,
              'altitude_meters': 0.0,
              'speed_mps': spd,
              'bearing_degrees': brg,
              'recorded_at': DateTime.fromMillisecondsSinceEpoch(epochSec * 1000, isUtc: true).toIso8601String(),
              'is_gap': isGap ? 1 : 0,
              'sync_status': chunk['sync_status'],
            });
          }
        } catch (e) {
          debugPrint('[TrackingDatabase] Error decoding chunk ${chunk['chunk_uuid']}: $e');
        }
      }
      return reconstructed;
    }

    return [];
  }

  /// Rekey session UUID across offline sessions, route chunks, and points when server provides canonical UUID
  Future<void> rekeySessionUuid(String oldSessionUuid, String newSessionUuid) async {
    if (oldSessionUuid == newSessionUuid) return;

    if (_useMemoryFallback) {
      for (final s in _webOfflineSessions) {
        if (s['session_uuid'] == oldSessionUuid) {
          s['session_uuid'] = newSessionUuid;
        }
      }
      for (final c in _webOfflineChunks) {
        if (c['session_uuid'] == oldSessionUuid) {
          c['session_uuid'] = newSessionUuid;
          final String chunkUuid = c['chunk_uuid'] ?? '';
          if (chunkUuid.startsWith(oldSessionUuid)) {
            c['chunk_uuid'] = chunkUuid.replaceFirst(oldSessionUuid, newSessionUuid);
          }
        }
      }
      for (final p in _webOfflinePoints) {
        if (p['session_uuid'] == oldSessionUuid) {
          p['session_uuid'] = newSessionUuid;
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
        'offline_route_chunks',
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

  /// Returns total count of persisted route points/vertices for a given session
  Future<int> getPointCount(String sessionUuid) async {
    if (_useMemoryFallback) {
      final chunkPoints = _webOfflineChunks
          .where((c) => c['session_uuid'] == sessionUuid)
          .fold<int>(0, (sum, c) => sum + ((c['point_count'] ?? 0) as int));
      if (chunkPoints > 0) return chunkPoints;
      return _webOfflinePoints.where((p) => p['session_uuid'] == sessionUuid).length;
    }
    final db = await database;
    if (db == null) return 0;

    final chunkRes = await db.rawQuery(
      'SELECT SUM(point_count) as total_pts FROM offline_route_chunks WHERE session_uuid = ?',
      [sessionUuid],
    );
    if (chunkRes.isNotEmpty && chunkRes.first['total_pts'] != null) {
      return (chunkRes.first['total_pts'] as num).toInt();
    }

    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_route_points WHERE session_uuid = ?',
      [sessionUuid],
    );
    if (res.isNotEmpty && res.first['count'] != null) {
      return (res.first['count'] as num).toInt();
    }
    return 0;
  }

  /// Returns total count of all pending points and chunks across all sessions waiting for upload
  Future<int> getPendingPointCount() async {
    if (_useMemoryFallback) {
      return _webOfflineChunks.where((c) => c['sync_status'] == 'PENDING').length +
             _webOfflinePoints.where((p) => p['sync_status'] == 'PENDING').length;
    }
    final db = await database;
    if (db == null) return 0;
    final chunkRes = await db.rawQuery("SELECT COUNT(*) as cnt FROM offline_route_chunks WHERE sync_status = 'PENDING'");
    final ptRes = await db.rawQuery("SELECT COUNT(*) as cnt FROM offline_route_points WHERE sync_status = 'PENDING'");
    int total = 0;
    if (chunkRes.isNotEmpty && chunkRes.first['cnt'] != null) {
      total += (chunkRes.first['cnt'] as num).toInt();
    }
    if (ptRes.isNotEmpty && ptRes.first['cnt'] != null) {
      total += (ptRes.first['cnt'] as num).toInt();
    }
    return total;
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

  // --- Offline Interruption Event Operations ---

  Future<void> recordInterruptionEvent({
    required String eventUuid,
    required String sessionUuid,
    required int userId,
    String? deviceId,
    required String reasonCode,
    required String description,
    required DateTime detectedAt,
    DateTime? lastKnownFixAt,
    String severity = 'WARNING',
    Map<String, dynamic>? diagnostics,
    bool isConfirmed = true,
  }) async {
    final row = <String, dynamic>{
      'event_uuid': eventUuid,
      'session_uuid': sessionUuid,
      'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      'reason_code': reasonCode,
      'description': description,
      'severity': severity,
      'detected_at': detectedAt.toIso8601String(),
      if (lastKnownFixAt != null) 'last_known_location_time': lastKnownFixAt.toIso8601String(),
      if (diagnostics != null) 'diagnostic_details': jsonEncode(diagnostics),
      'is_confirmed': isConfirmed ? 1 : 0,
      'recovery_outcome': 'UNRESOLVED',
      'sync_status': 'PENDING',
    };

    if (_useMemoryFallback) {
      final existingIndex = _webOfflineInterruptionEvents.indexWhere((e) => e['event_uuid'] == eventUuid);
      final ev = Map<String, dynamic>.from(row);
      if (existingIndex >= 0) {
        _webOfflineInterruptionEvents[existingIndex] = ev;
      } else {
        ev['id'] = _webEventSeq++;
        _webOfflineInterruptionEvents.add(ev);
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    await db.insert(
      'offline_interruption_events',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> closeInterruptionEvent({
    required String sessionUuid,
    String? eventUuid,
    String? reasonCode,
    required DateTime recoveredAt,
    int? durationSeconds,
    String outcome = 'RESOLVED',
  }) async {
    final recIso = recoveredAt.toIso8601String();
    String? closedUuid = eventUuid;

    if (_useMemoryFallback) {
      for (final e in _webOfflineInterruptionEvents) {
        if (e['session_uuid'] == sessionUuid && e['recovery_outcome'] == 'UNRESOLVED') {
          if (eventUuid == null || e['event_uuid'] == eventUuid) {
            closedUuid = e['event_uuid'] as String;
            final detAtStr = e['detected_at'] as String?;
            int dur = durationSeconds ?? 0;
            if (durationSeconds == null && detAtStr != null) {
              try {
                dur = recoveredAt.difference(DateTime.parse(detAtStr)).inSeconds.abs();
              } catch (_) {}
            }
            e['recovered_at'] = recIso;
            e['duration_seconds'] = dur;
            e['recovery_outcome'] = outcome;
            e['sync_status'] = 'PENDING';
            break;
          }
        }
      }
      return closedUuid;
    }

    final db = await database;
    if (db == null) return null;

    // Find target event to close and calculate duration if needed
    String findWhere = 'session_uuid = ? AND recovery_outcome = ?';
    List<dynamic> findArgs = [sessionUuid, 'UNRESOLVED'];
    if (eventUuid != null) {
      findWhere += ' AND event_uuid = ?';
      findArgs.add(eventUuid);
    } else if (reasonCode != null) {
      findWhere += ' AND reason_code = ?';
      findArgs.add(reasonCode);
    }

    final existing = await db.query(
      'offline_interruption_events',
      where: findWhere,
      whereArgs: findArgs,
      orderBy: 'detected_at DESC',
      limit: 1,
    );

    if (existing.isNotEmpty) {
      closedUuid = existing.first['event_uuid'] as String;
      int dur = durationSeconds ?? 0;
      if (durationSeconds == null) {
        final detAtStr = existing.first['detected_at'] as String?;
        if (detAtStr != null) {
          try {
            dur = recoveredAt.difference(DateTime.parse(detAtStr)).inSeconds.abs();
          } catch (_) {}
        }
      }

      await db.update(
        'offline_interruption_events',
        {
          'recovered_at': recIso,
          'duration_seconds': dur,
          'recovery_outcome': outcome,
          'sync_status': 'PENDING',
        },
        where: 'event_uuid = ?',
        whereArgs: [closedUuid],
      );
    }

    return closedUuid;
  }

  Future<List<Map<String, dynamic>>> getPendingInterruptionEvents() async {
    if (_useMemoryFallback) {
      return List<Map<String, dynamic>>.from(
        _webOfflineInterruptionEvents.where((e) => e['sync_status'] == 'PENDING'),
      );
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_interruption_events',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'detected_at ASC',
    );
  }

  Future<void> markInterruptionEventsSynced(List<String> eventUuids) async {
    if (eventUuids.isEmpty) return;
    if (_useMemoryFallback) {
      for (final e in _webOfflineInterruptionEvents) {
        if (eventUuids.contains(e['event_uuid'])) {
          e['sync_status'] = 'SYNCED';
        }
      }
      return;
    }
    final db = await database;
    if (db == null) return;
    final placeholders = List.filled(eventUuids.length, '?').join(',');
    await db.update(
      'offline_interruption_events',
      {'sync_status': 'SYNCED'},
      where: 'event_uuid IN ($placeholders)',
      whereArgs: eventUuids,
    );
  }

  Future<List<Map<String, dynamic>>> getInterruptionHistory(String sessionUuid) async {
    if (_useMemoryFallback) {
      final list = _webOfflineInterruptionEvents
          .where((e) => e['session_uuid'] == sessionUuid)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      list.sort((a, b) => (a['detected_at'] as String).compareTo(b['detected_at'] as String));
      return list;
    }
    final db = await database;
    if (db == null) return [];
    return await db.query(
      'offline_interruption_events',
      where: 'session_uuid = ?',
      whereArgs: [sessionUuid],
      orderBy: 'detected_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getActiveInterruption(String sessionUuid) async {
    if (_useMemoryFallback) {
      final matches = _webOfflineInterruptionEvents
          .where((e) => e['session_uuid'] == sessionUuid && e['recovery_outcome'] == 'UNRESOLVED')
          .toList();
      return matches.isNotEmpty ? Map<String, dynamic>.from(matches.last) : null;
    }
    final db = await database;
    if (db == null) return null;
    final res = await db.query(
      'offline_interruption_events',
      where: 'session_uuid = ? AND recovery_outcome = ?',
      whereArgs: [sessionUuid, 'UNRESOLVED'],
      orderBy: 'detected_at DESC',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }
}
