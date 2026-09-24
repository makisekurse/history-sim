import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_config.dart';
import '../models/chapter_node.dart';

/// 本地持久化存储服务
class StorageService {
  static const String _keyConfig = 'deng1949_game_config';
  static const String _keyHistory = 'deng1949_history_nodes';

  /// 读取游戏配置
  static Future<GameConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyConfig);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr);
        return GameConfig.fromJson(map);
      } catch (_) {}
    }
    return GameConfig();
  }

  /// 保存游戏配置
  static Future<void> saveConfig(GameConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyConfig, jsonEncode(config.toJson()));
  }

  /// 读取章节历史
  static Future<List<ChapterNode>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyHistory);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        return list.map((e) => ChapterNode.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return [];
  }

  /// 保存章节历史
  static Future<void> saveHistory(List<ChapterNode> history) async {
    final prefs = await SharedPreferences.getInstance();
    final list = history.map((e) => e.toJson()).toList();
    await prefs.setString(_keyHistory, jsonEncode(list));
  }

  /// 清除历史（重启推演）
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}
