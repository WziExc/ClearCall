import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/call_record.dart';

/// 通话记录本地数据库
///
/// 使用 sqflite 实现单例模式，支持：
/// - 插入通话记录（通话结束后自动保存）
/// - 查询最近 50 条记录（按时间倒序）
/// - 删除单条记录
class CallHistoryDB {
  static final CallHistoryDB _instance = CallHistoryDB._();
  factory CallHistoryDB() => _instance;
  CallHistoryDB._();

  Database? _db;

  /// 获取数据库实例（懒加载）
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'clearcall_history.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE call_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            targetId TEXT NOT NULL,
            targetName TEXT NOT NULL,
            startTime INTEGER NOT NULL,
            endTime INTEGER,
            durationSeconds INTEGER,
            isFriendCall INTEGER NOT NULL DEFAULT 0,
            callType TEXT NOT NULL DEFAULT 'video',
            direction TEXT NOT NULL DEFAULT 'outgoing',
            answered INTEGER NOT NULL DEFAULT 1
          )
        ''');
        // 索引：按时间查询
        await db.execute('''
          CREATE INDEX idx_start_time ON call_records(startTime DESC)
        ''');
      },
    );
  }

  /// 插入一条通话记录
  Future<int> insert(CallRecord record) async {
    final db = await database;
    return db.insert('call_records', record.toMap());
  }

  /// 获取所有通话记录（最近 50 条，按时间倒序）
  Future<List<CallRecord>> getAll({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'call_records',
      orderBy: 'startTime DESC',
      limit: limit,
    );
    return maps.map((m) => CallRecord.fromMap(m)).toList();
  }

  /// 删除单条记录
  Future<int> delete(int id) async {
    final db = await database;
    return db.delete(
      'call_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除所有记录
  Future<int> clearAll() async {
    final db = await database;
    return db.delete('call_records');
  }
}
