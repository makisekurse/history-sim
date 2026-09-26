import 'package:flutter/foundation.dart';

/// 运行日志条目。
class LogEntry {
  final DateTime time;
  final String level; // I / W / E
  final String tag;
  final String message;

  LogEntry(this.time, this.level, this.tag, this.message);

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get stamp {
    final d = time;
    return '${d.year}-${_two(d.month)}-${_two(d.day)} '
        '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.'
        '${d.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  String toString() => '$stamp [$level] $tag — $message';
}

/// 运行日志 —— 内存环形缓冲 + 一键导出，用于开发排障。
///
/// 只记**诊断信息**（请求参数、SSE 分块、解析判定、重试链路、错误详情），
/// 不记 API Key。开关与详细级别由 [enabled] / [verbose] 控制，
/// 默认关闭 —— 不开启时 [log] 直接返回，零开销。
class RuntimeLog {
  RuntimeLog._();

  /// 上限：约 2000 条 / 2MB，超出丢最旧。
  static const int maxEntries = 2000;
  static const int maxMessageChars = 600;

  static final List<LogEntry> _buf = <LogEntry>[];

  /// 总开关（设置页可切）。
  static bool enabled = false;

  /// 详细模式：额外记录模型原文片段与逐条 SSE 行。
  static bool verbose = false;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static int get count => _buf.length;

  static void log(
    String level,
    String tag,
    String message, {
    bool detail = false,
  }) {
    if (!enabled) return;
    if (detail && !verbose) return;

    var msg = message.replaceAll('\n', ' ⏎ ');
    if (msg.length > maxMessageChars) {
      msg = '${msg.substring(0, maxMessageChars)}…(+${msg.length - maxMessageChars})';
    }
    _buf.add(LogEntry(DateTime.now(), level, tag, msg));
    while (_buf.length > maxEntries) {
      _buf.removeAt(0);
    }
    revision.value++;
  }

  static void i(String tag, String message, {bool detail = false}) =>
      log('I', tag, message, detail: detail);

  static void w(String tag, String message, {bool detail = false}) =>
      log('W', tag, message, detail: detail);

  static void e(String tag, String message, {bool detail = false}) =>
      log('E', tag, message, detail: detail);

  static List<LogEntry> entries() => List<LogEntry>.from(_buf);

  static void clear() {
    _buf.clear();
    revision.value++;
  }

  /// 导出为可读文本（表头带环境信息，方便对号入座）。
  static String dump() {
    final sb = StringBuffer()
      ..writeln('# 拟境 · 运行日志')
      ..writeln('# 导出时间：${DateTime.now().toIso8601String()}')
      ..writeln('# 条目数：${_buf.length}  详细模式：${verbose ? '开' : '关'}')
      ..writeln('# 平台：${defaultTargetPlatform.name}')
      ..writeln('-' * 60);
    for (final e in _buf) {
      sb.writeln(e.toString());
    }
    return sb.toString();
  }
}
