import 'dart:convert';

import '../data/prefs_store.dart';
import '../models/save_slot.dart';

/// 存档槽管理。
///
/// 旧版只有一个隐式的「当前进度」，一旦重启就只剩第一幕。
/// 现在支持多槽位：不同世界书、不同局互不覆盖。
class SaveService {
  SaveService._();

  static const String _key = 'nijing_saves_v1';

  /// 读取存档。
  ///
  /// ⚠️ 默认**不返回自动备份**（`backup_*`）—— 它们不是用户真实在玩的推演，
  /// 混进列表会让「我一共玩了两幕，怎么有三个推演」这种困惑出现。
  /// 需要备份时显式传 `includeBackups: true`。
  static Future<List<SaveSlot>> loadAll({bool includeBackups = false}) async {
    final slots = await _loadAllRaw();
    if (!includeBackups) slots.removeWhere((s) => s.isBackup);
    return slots;
  }

  /// 只取自动备份。
  static Future<List<SaveSlot>> loadBackups() async {
    final slots = await _loadAllRaw();
    return slots.where((s) => s.isBackup).toList();
  }

  /// 底层读取：**包含全部**槽位。写入路径必须用它，
  /// 否则 `saveAll` 会把备份从盘上抹掉。
  static Future<List<SaveSlot>> _loadAllRaw() async {
    final raw = await PrefsStore.getString(_key);
    if (raw == null || raw.isEmpty) return <SaveSlot>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final slots = list
          .whereType<Map>()
          .map((e) => SaveSlot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      slots.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return slots;
    } catch (_) {
      return <SaveSlot>[];
    }
  }

  static Future<void> saveAll(List<SaveSlot> slots) async {
    // 存档是「不能丢」的数据，直接落盘，不走防抖。
    await PrefsStore.setString(
      _key,
      jsonEncode(slots.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> upsert(SaveSlot slot) async {
    slot.updatedAt = DateTime.now();
    // ⚠️ 必须用 _loadAllRaw：用 loadAll 的话会把其它备份挤掉
    final all = await _loadAllRaw();
    final idx = all.indexWhere((e) => e.id == slot.id);
    if (idx >= 0) {
      all[idx] = slot;
    } else {
      all.add(slot);
    }
    await saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await _loadAllRaw();
    all.removeWhere((e) => e.id == id);
    await saveAll(all);
  }

  static Future<SaveSlot?> findById(String id) async {
    final all = await _loadAllRaw();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 导出成可分享的 JSON 文本。
  static String exportSlot(SaveSlot slot) =>
      const JsonEncoder.withIndent('  ').convert(slot.toJson());

  /// 从 JSON 文本导入一个存档。
  static SaveSlot importSlot(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('存档格式不正确');
    return SaveSlot.fromJson(Map<String, dynamic>.from(decoded));
  }
}
