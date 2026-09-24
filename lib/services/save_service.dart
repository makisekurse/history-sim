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

  static Future<List<SaveSlot>> loadAll() async {
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
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.id == slot.id);
    if (idx >= 0) {
      all[idx] = slot;
    } else {
      all.add(slot);
    }
    await saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    await saveAll(all);
  }

  static Future<SaveSlot?> findById(String id) async {
    final all = await loadAll();
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
