import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_record.dart';
import '../services/call_history_db.dart';

/// 通话记录列表状态
typedef CallHistoryState = AsyncValue<List<CallRecord>>;

/// 通话记录 Provider
///
/// 管理本地通话记录的增删查，通过 sqflite 持久化。
/// UI 通过 `ref.watch(callHistoryProvider)` 响应记录变更。
final callHistoryProvider =
    StateNotifierProvider<CallHistoryNotifier, CallHistoryState>(
  (ref) => CallHistoryNotifier(),
);

class CallHistoryNotifier extends StateNotifier<CallHistoryState> {
  final CallHistoryDB _db = CallHistoryDB();

  CallHistoryNotifier() : super(const AsyncLoading()) {
    loadRecords();
  }

  /// 从数据库加载所有记录
  Future<void> loadRecords() async {
    state = const AsyncLoading();
    try {
      final records = await _db.getAll();
      state = AsyncData(records);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// 新增一条通话记录（通话结束时调用）
  Future<void> addRecord(CallRecord record) async {
    try {
      await _db.insert(record);
      // 重新加载以获取最新列表
      await loadRecords();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// 删除一条记录
  Future<void> deleteRecord(int id) async {
    try {
      await _db.delete(id);
      await loadRecords();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
