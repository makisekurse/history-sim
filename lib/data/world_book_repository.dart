import 'dart:convert';

import '../models/world_book.dart';
import 'prefs_store.dart';

/// 世界书的本地仓库。
///
/// 应用**不内置任何世界书** —— 这里是空的，全部由用户新建或导入。
class WorldBookRepository {
  WorldBookRepository._();

  static const String _key = 'histsim_worldbooks_v1';

  static Future<List<WorldBook>> loadAll() async {
    final raw = await PrefsStore.getString(_key);
    if (raw == null || raw.isEmpty) return <WorldBook>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => WorldBook.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <WorldBook>[];
    }
  }

  static Future<void> saveAll(List<WorldBook> books) async {
    final raw = jsonEncode(books.map((e) => e.toJson()).toList());
    await PrefsStore.setString(_key, raw);
  }

  static Future<void> upsert(WorldBook book) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.id == book.id);
    if (idx >= 0) {
      all[idx] = book;
    } else {
      all.add(book);
    }
    await saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    await saveAll(all);
  }

  static Future<WorldBook?> findById(String id) async {
    final all = await loadAll();
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }
}
