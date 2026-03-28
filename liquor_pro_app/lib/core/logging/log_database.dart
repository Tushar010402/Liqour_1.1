import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

/// Industrial-grade SQLite database for persistent logging
///
/// Features:
/// - Persists logs across app restarts
/// - Auto-cleanup of logs older than 7 days
/// - Efficient batch operations for sync
/// - Indexed queries for filtering
class LogDatabase {
  static final LogDatabase _instance = LogDatabase._internal();
  factory LogDatabase() => _instance;
  LogDatabase._internal();

  static Database? _database;
  static const String _dbName = 'liquor_pro_logs.db';
  static const int _dbVersion = 1;

  // Retention period in days
  static const int retentionDays = 7;

  /// Get database instance (lazy initialization)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    if (kDebugMode) {
      print('📂 LogDatabase: Initializing at $path');
    }

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    if (kDebugMode) {
      print('📂 LogDatabase: Creating tables...');
    }

    // Log entries table
    await db.execute('''
      CREATE TABLE log_entries (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL,
        tag TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        session_id TEXT NOT NULL,
        metadata TEXT,
        is_synced INTEGER DEFAULT 0,
        synced_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        device_id TEXT NOT NULL,
        device_model TEXT,
        os_version TEXT,
        app_version TEXT NOT NULL,
        user_id TEXT,
        tenant_id TEXT,
        log_count INTEGER DEFAULT 0,
        error_count INTEGER DEFAULT 0,
        screens_visited TEXT DEFAULT '[]'
      )
    ''');

    // Network requests table (detailed API inspection)
    await db.execute('''
      CREATE TABLE network_requests (
        id TEXT PRIMARY KEY,
        log_entry_id TEXT,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        status_code INTEGER,
        duration_ms INTEGER,
        request_headers TEXT,
        request_body TEXT,
        response_headers TEXT,
        response_body TEXT,
        error_message TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (log_entry_id) REFERENCES log_entries(id)
      )
    ''');

    // Create indexes for efficient querying
    await db.execute('CREATE INDEX idx_log_timestamp ON log_entries(timestamp)');
    await db.execute('CREATE INDEX idx_log_level ON log_entries(level)');
    await db.execute('CREATE INDEX idx_log_tag ON log_entries(tag)');
    await db.execute('CREATE INDEX idx_log_session ON log_entries(session_id)');
    await db.execute('CREATE INDEX idx_log_synced ON log_entries(is_synced)');
    await db.execute('CREATE INDEX idx_session_started ON sessions(started_at)');
    await db.execute('CREATE INDEX idx_network_timestamp ON network_requests(timestamp)');

    if (kDebugMode) {
      print('✅ LogDatabase: Tables created successfully');
    }
  }

  /// Called when database is opened
  Future<void> _onOpen(Database db) async {
    // Run cleanup of old logs
    await _cleanupOldLogs(db);
  }

  /// Cleanup logs older than retention period
  Future<void> _cleanupOldLogs(Database db) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    final cutoffStr = cutoffDate.toIso8601String();

    try {
      // Delete old network requests first (foreign key constraint)
      final networkDeleted = await db.delete(
        'network_requests',
        where: 'timestamp < ?',
        whereArgs: [cutoffStr],
      );

      // Delete old log entries
      final logsDeleted = await db.delete(
        'log_entries',
        where: 'timestamp < ?',
        whereArgs: [cutoffStr],
      );

      // Delete old sessions
      final sessionsDeleted = await db.delete(
        'sessions',
        where: 'started_at < ?',
        whereArgs: [cutoffStr],
      );

      if (kDebugMode && (logsDeleted > 0 || sessionsDeleted > 0)) {
        print('🧹 LogDatabase: Cleaned up $logsDeleted logs, $networkDeleted network requests, $sessionsDeleted sessions older than $retentionDays days');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ LogDatabase: Cleanup error: $e');
      }
    }
  }

  // ==================== LOG ENTRIES ====================

  /// Insert a log entry
  Future<void> insertLog(Map<String, dynamic> log) async {
    final db = await database;
    await db.insert(
      'log_entries',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple log entries (batch)
  Future<void> insertLogs(List<Map<String, dynamic>> logs) async {
    final db = await database;
    final batch = db.batch();
    for (final log in logs) {
      batch.insert('log_entries', log, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Get logs with filters
  Future<List<Map<String, dynamic>>> getLogs({
    String? level,
    String? tag,
    String? sessionId,
    String? search,
    DateTime? after,
    DateTime? before,
    bool? isSynced,
    int? limit,
    int? offset,
  }) async {
    final db = await database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (level != null) {
      where.add('level = ?');
      whereArgs.add(level);
    }
    if (tag != null) {
      where.add('tag LIKE ?');
      whereArgs.add('%$tag%');
    }
    if (sessionId != null) {
      where.add('session_id = ?');
      whereArgs.add(sessionId);
    }
    if (search != null) {
      where.add('(message LIKE ? OR tag LIKE ?)');
      whereArgs.add('%$search%');
      whereArgs.add('%$search%');
    }
    if (after != null) {
      where.add('timestamp >= ?');
      whereArgs.add(after.toIso8601String());
    }
    if (before != null) {
      where.add('timestamp <= ?');
      whereArgs.add(before.toIso8601String());
    }
    if (isSynced != null) {
      where.add('is_synced = ?');
      whereArgs.add(isSynced ? 1 : 0);
    }

    return await db.query(
      'log_entries',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get unsynced logs for batch upload
  Future<List<Map<String, dynamic>>> getUnsyncedLogs({int limit = 50}) async {
    final db = await database;
    return await db.query(
      'log_entries',
      where: 'is_synced = 0',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Mark logs as synced
  Future<void> markLogsSynced(List<String> ids) async {
    if (ids.isEmpty) return;

    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE log_entries SET is_synced = 1, synced_at = ? WHERE id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...ids],
    );
  }

  /// Get log count by level
  Future<Map<String, int>> getLogCountByLevel() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT level, COUNT(*) as count
      FROM log_entries
      GROUP BY level
    ''');

    final counts = <String, int>{};
    for (final row in result) {
      counts[row['level'] as String] = row['count'] as int;
    }
    return counts;
  }

  /// Get unique tags
  Future<List<String>> getUniqueTags() async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT tag FROM log_entries ORDER BY tag');
    return result.map((row) => row['tag'] as String).toList();
  }

  /// Get total log count
  Future<int> getTotalLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM log_entries');
    return result.first['count'] as int;
  }

  /// Get unsynced log count
  Future<int> getUnsyncedLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM log_entries WHERE is_synced = 0');
    return result.first['count'] as int;
  }

  /// Clear all logs (for debugging)
  Future<void> clearAllLogs() async {
    final db = await database;
    await db.delete('network_requests');
    await db.delete('log_entries');
    await db.delete('sessions');

    if (kDebugMode) {
      print('🗑️ LogDatabase: All logs cleared');
    }
  }

  // ==================== SESSIONS ====================

  /// Insert or update a session
  Future<void> upsertSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert(
      'sessions',
      session,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update session end time and stats
  Future<void> updateSessionEnd(String sessionId) async {
    final db = await database;

    // Get log counts for this session
    final logCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM log_entries WHERE session_id = ?',
      [sessionId],
    );
    final errorCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM log_entries WHERE session_id = ? AND level = ?',
      [sessionId, 'error'],
    );

    await db.update(
      'sessions',
      {
        'ended_at': DateTime.now().toIso8601String(),
        'log_count': logCount.first['count'],
        'error_count': errorCount.first['count'],
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Get sessions
  Future<List<Map<String, dynamic>>> getSessions({int? limit, int? offset}) async {
    final db = await database;
    return await db.query(
      'sessions',
      orderBy: 'started_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get session by ID
  Future<Map<String, dynamic>?> getSession(String sessionId) async {
    final db = await database;
    final results = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ==================== NETWORK REQUESTS ====================

  /// Insert a network request
  Future<void> insertNetworkRequest(Map<String, dynamic> request) async {
    final db = await database;
    await db.insert(
      'network_requests',
      request,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get network requests
  Future<List<Map<String, dynamic>>> getNetworkRequests({
    String? sessionId,
    int? statusCode,
    String? method,
    DateTime? after,
    DateTime? before,
    int? limit,
    int? offset,
  }) async {
    final db = await database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (sessionId != null) {
      where.add('log_entry_id IN (SELECT id FROM log_entries WHERE session_id = ?)');
      whereArgs.add(sessionId);
    }
    if (statusCode != null) {
      where.add('status_code = ?');
      whereArgs.add(statusCode);
    }
    if (method != null) {
      where.add('method = ?');
      whereArgs.add(method);
    }
    if (after != null) {
      where.add('timestamp >= ?');
      whereArgs.add(after.toIso8601String());
    }
    if (before != null) {
      where.add('timestamp <= ?');
      whereArgs.add(before.toIso8601String());
    }

    return await db.query(
      'network_requests',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get network request by ID
  Future<Map<String, dynamic>?> getNetworkRequest(String id) async {
    final db = await database;
    final results = await db.query(
      'network_requests',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get network request statistics
  Future<Map<String, dynamic>> getNetworkStats({String? sessionId}) async {
    final db = await database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (sessionId != null) {
      whereClause = 'WHERE log_entry_id IN (SELECT id FROM log_entries WHERE session_id = ?)';
      whereArgs = [sessionId];
    }

    final total = await db.rawQuery(
      'SELECT COUNT(*) as count FROM network_requests $whereClause',
      whereArgs,
    );

    final errors = await db.rawQuery(
      'SELECT COUNT(*) as count FROM network_requests $whereClause ${whereClause.isEmpty ? 'WHERE' : 'AND'} (status_code >= 400 OR error_message IS NOT NULL)',
      whereArgs,
    );

    final avgDuration = await db.rawQuery(
      'SELECT AVG(duration_ms) as avg FROM network_requests $whereClause ${whereClause.isEmpty ? 'WHERE' : 'AND'} duration_ms IS NOT NULL',
      whereArgs,
    );

    return {
      'total': total.first['count'] as int,
      'errors': errors.first['count'] as int,
      'avgDurationMs': (avgDuration.first['avg'] as num?)?.toInt() ?? 0,
    };
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
