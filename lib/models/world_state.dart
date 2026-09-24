/// 世界状态 —— 结构化的「此刻是什么状态」。
///
/// 与编年史的分工（必须严格区分，否则两套上下文会打架）：
///
/// | | WorldState | 编年史 |
/// |---|---|---|
/// | 体裁 | 结构化条目 | 散文叙事 |
/// | 回答 | 现在是什么状态 | 过去发生过什么 |
/// | 时态 | 只写当下 | 只用过去时 |
/// | 体积 | 有硬上限 | 会累积增长 |
///
/// 判定规则：一条信息，如果**回滚到第 5 幕后就不成立了** → 归 WorldState；
/// 如果**永远成立** → 归编年史。
class WorldState {
  /// 剧中时间
  String time;

  /// 当前位置
  String location;

  /// 已知事实（当前有效）
  List<String> facts;

  /// 人物关系：姓名 → 当前态度
  Map<String, String> relations;

  /// 进行中的事件
  List<String> events;

  WorldState({
    this.time = '',
    this.location = '',
    List<String>? facts,
    Map<String, String>? relations,
    List<String>? events,
  })  : facts = facts ?? <String>[],
        relations = relations ?? <String, String>{},
        events = events ?? <String>[];

  // ---- 上限（按 GPT 建议：用总预算 + 宽松条数，而不是每类 5 条 / 每条 40 字）----

  static const int maxFacts = 12;
  static const int maxRelations = 12;
  static const int maxEvents = 8;

  /// 单条上限。旧方案定 40 字太狠，会把关键信息砍断。
  static const int maxItemChars = 120;

  /// 整块上限，防止 state 每幕重复进 prompt 把 token 撑爆。
  static const int maxTotalChars = 4000;

  bool get isEmpty =>
      time.trim().isEmpty &&
      location.trim().isEmpty &&
      facts.isEmpty &&
      relations.isEmpty &&
      events.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 一行摘要，给游玩页顶部那条极轻量的状态用。
  String get inlineSummary {
    final parts = <String>[
      if (location.trim().isNotEmpty) location.trim(),
      if (time.trim().isNotEmpty) time.trim(),
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'time': time,
        'location': location,
        'facts': facts,
        'relations': relations,
        'events': events,
      };

  factory WorldState.fromJson(Map<String, dynamic> json) => WorldState(
        time: (json['time'] ?? '').toString(),
        location: (json['location'] ?? '').toString(),
        facts: _strList(json['facts']),
        relations: _strMap(json['relations']),
        events: _strList(json['events']),
      );

  WorldState copy() => WorldState(
        time: time,
        location: location,
        facts: List<String>.from(facts),
        relations: Map<String, String>.from(relations),
        events: List<String>.from(events),
      );

  static List<String> _strList(Object? v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return <String>[];
  }

  static Map<String, String> _strMap(Object? v) {
    if (v is Map) {
      final out = <String, String>{};
      v.forEach((k, val) {
        final key = k.toString().trim();
        if (key.isNotEmpty) out[key] = val.toString().trim();
      });
      return out;
    }
    return <String, String>{};
  }
}
