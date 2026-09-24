import '../models/world_state.dart';

/// WorldState 的解析、合并、渲染。
///
/// 设计原则（来自方案评审）：
/// - **模型只提出状态变化，Dart 负责校验 / 合并 / 截断 / 持久化**。
///   不让模型每幕凭空重写整个世界。
/// - 限制用**总字符预算 + 宽松条数**，而不是「每类 5 条 / 每条 40 字」那种
///   硬编码截断 —— 那样第 6 个真正重要的事实会被直接挤掉。
class WorldStateService {
  WorldStateService._();

  /// 模型 `<state>` 块里允许出现的键（中英双写，容错）。
  static const Map<String, String> _keyAliases = <String, String>{
    '时间': 'time',
    '地点': 'location',
    '位置': 'location',
    '事实': 'facts',
    '已知事实': 'facts',
    '关键事实': 'facts',
    '关系': 'relations',
    '人物关系': 'relations',
    '事件': 'events',
    '进行中事件': 'events',
    '进行中的事件': 'events',
    'time': 'time',
    'location': 'location',
    'facts': 'facts',
    'relations': 'relations',
    'events': 'events',
  };

  /// 解析 `<state>` 块的正文。
  ///
  /// 容忍：中英文冒号、全角分号/半角分号/竖线混用、多余空行、键名大小写。
  /// **解析失败不抛异常** —— 返回空 state，由调用方保留上一幕的状态。
  static WorldState parse(String raw) {
    final state = WorldState();
    if (raw.trim().isEmpty) return state;

    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 找第一个冒号（中/英文）
      final idx = _firstColon(trimmed);
      if (idx <= 0) continue;

      final rawKey = _clean(trimmed.substring(0, idx)).replaceAll('*', '');
      final value = trimmed.substring(idx + 1).trim();
      if (value.isEmpty) continue;

      final key = _keyAliases[rawKey] ?? _keyAliases[rawKey.toLowerCase()];
      if (key == null) continue;

      switch (key) {
        case 'time':
          state.time = _clean(value);
          break;
        case 'location':
          state.location = _clean(value);
          break;
        case 'facts':
          state.facts = _splitList(value);
          break;
        case 'events':
          state.events = _splitList(value);
          break;
        case 'relations':
          for (final item in _splitList(value)) {
            final parts = item.split('|');
            final name = parts.first.trim();
            if (name.isEmpty) continue;
            state.relations[name] =
                parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
          }
          break;
      }
    }
    return _cap(state);
  }

  /// 把新状态合并进旧状态。
  ///
  /// - `time` / `location`：新值非空就覆盖
  /// - `facts` / `events`：模型给的是**当前完整列表**，直接替换
  /// - `relations`：模型给的是**增量**，逐条覆盖但**不丢弃模型没提到的旧关系**
  ///   （关系是长期资产，忘了比记错更糟）
  static WorldState merge(WorldState previous, WorldState incoming) {
    final out = previous.copy();

    if (incoming.time.trim().isNotEmpty) out.time = incoming.time.trim();
    if (incoming.location.trim().isNotEmpty) {
      out.location = incoming.location.trim();
    }
    if (incoming.facts.isNotEmpty) out.facts = incoming.facts;
    if (incoming.events.isNotEmpty) out.events = incoming.events;
    incoming.relations.forEach((k, v) {
      out.relations[k] = v;
    });

    return _cap(out);
  }

  /// 渲染成塞进 system prompt 的一段。
  static String renderForPrompt(WorldState state) {
    if (state.isEmpty) return '';
    final sb = StringBuffer();
    if (state.time.trim().isNotEmpty) sb.writeln('时间：${state.time.trim()}');
    if (state.location.trim().isNotEmpty) {
      sb.writeln('地点：${state.location.trim()}');
    }
    if (state.facts.isNotEmpty) {
      sb.writeln('已知事实：${state.facts.join('；')}');
    }
    if (state.relations.isNotEmpty) {
      sb.writeln(
        '人物关系：${state.relations.entries.map((e) => '${e.key}|${e.value}').join('；')}',
      );
    }
    if (state.events.isNotEmpty) {
      sb.writeln('进行中事件：${state.events.join('；')}');
    }
    return sb.toString().trim();
  }

  /// 校验 + 截断。所有写入口都必须过这一道。
  static WorldState _cap(WorldState s) {
    s.time = _truncate(s.time, WorldState.maxItemChars);
    s.location = _truncate(s.location, WorldState.maxItemChars);

    s.facts = _dedup(s.facts)
        .take(WorldState.maxFacts)
        .map((e) => _truncate(e, WorldState.maxItemChars))
        .toList();

    s.events = _dedup(s.events)
        .take(WorldState.maxEvents)
        .map((e) => _truncate(e, WorldState.maxItemChars))
        .toList();

    // 关系按插入顺序保留前 N 条（Dart 的 Map 保序）
    final capped = <String, String>{};
    for (final e in s.relations.entries) {
      if (capped.length >= WorldState.maxRelations) break;
      capped[e.key] = _truncate(e.value, WorldState.maxItemChars);
    }
    s.relations = capped;

    // 总预算兜底：超了就从尾部丢事件、再丢事实
    while (_totalChars(s) > WorldState.maxTotalChars) {
      if (s.events.isNotEmpty) {
        s.events.removeLast();
      } else if (s.facts.isNotEmpty) {
        s.facts.removeLast();
      } else if (s.relations.isNotEmpty) {
        s.relations.remove(s.relations.keys.last);
      } else {
        break;
      }
    }
    return s;
  }

  static int _totalChars(WorldState s) =>
      s.time.length +
      s.location.length +
      s.facts.fold<int>(0, (a, e) => a + e.length) +
      s.events.fold<int>(0, (a, e) => a + e.length) +
      s.relations.entries
          .fold<int>(0, (a, e) => a + e.key.length + e.value.length);

  static List<String> _dedup(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in input) {
      final t = item.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
    }
    return out;
  }

  /// 值里的多条用「；」「;」「|」分隔（竖线只在关系里当分隔，这里也容错）。
  static List<String> _splitList(String value) => value
      .split(RegExp(r'[；;\n]'))
      .map((e) => _clean(e))
      .where((e) => e.isNotEmpty)
      .toList();

  static String _clean(String s) => s.replaceFirst(_listMarker, '').trim();

  /// 去掉列表标记（`1. ` / `1、` / `- ` / `* ` / `• `），但**不动合法数字**。
  ///
  /// ⚠️ 早先写成 `^[\-\*\d\.\、\s]+`，会把「1949年11月23日」里的 `1949`
  /// 也当成序号吃掉，时间被解析成「年11月23日」。
  /// 现在要求数字后面必须跟一个分隔符才算列表标记。
  static final RegExp _listMarker =
      RegExp(r'^(?:\d+[\.\、\)）]\s*|[-*•]\s+)');

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  static int _firstColon(String line) {
    final a = line.indexOf('：');
    final b = line.indexOf(':');
    if (a < 0) return b;
    if (b < 0) return a;
    return a < b ? a : b;
  }
}
