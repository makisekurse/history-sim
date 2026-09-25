import 'chapter_node.dart';
import 'world_book.dart';
import 'world_state.dart';

/// 一个存档槽 = 一本世界书 + 一串推演记录 + 滚动编年史摘要 + 当前世界状态。
///
/// 存档里**内嵌世界书快照**，所以即使之后世界书被改或被删，
/// 老存档依然能完整打开。
///
/// ⚠️ 顶层这几个字段（history / chronicle / worldState）表示的是**最新**状态。
/// 要回滚到任意历史幕，必须靠 `ChapterNode.chronicleAfter` 与
/// `ChapterNode.worldStateAfter` 这两个**每幕快照** —— 顶层字段做不到。
class SaveSlot {
  final String id;
  String title;
  WorldBook worldBook;
  List<ChapterNode> history;

  /// 编年史滚动摘要：每若干幕压缩一次前情，塞进 system prompt，
  /// 解决「玩到第 20 幕模型已经忘了前面发生过什么」。
  String chronicle;

  /// 当前世界状态（结构化）。
  WorldState worldState;

  DateTime createdAt;
  DateTime updatedAt;

  SaveSlot({
    required this.id,
    required this.title,
    required this.worldBook,
    List<ChapterNode>? history,
    this.chronicle = '',
    WorldState? worldState,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : history = history ?? <ChapterNode>[],
        worldState = worldState ?? WorldState(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// 回滚前自动备份的槽位用这个前缀。
  ///
  /// ⚠️ 2026-09-25 修：备份以前和正常存档混在一个列表里，用户回滚一次
  /// 就凭空多出一个「推演」，数据管理里显示的数量也对不上。
  /// 现在用 id 前缀把两者区分开，备份**不进正常列表**。
  static const String backupIdPrefix = 'backup_';

  static String backupIdFor(String slotId) => '$backupIdPrefix$slotId';

  /// 这是不是一份自动备份（而非用户真实在玩的推演）。
  bool get isBackup => id.startsWith(backupIdPrefix);

  int get chapterCount => history.length;

  /// 最近一次落定的日期，用于列表页展示。
  String get latestDate => history.isEmpty ? '' : history.last.date;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'worldBook': worldBook.toJson(),
        'history': history.map((e) => e.toJson()).toList(),
        'chronicle': chronicle,
        'worldState': worldState.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SaveSlot.fromJson(Map<String, dynamic> json) {
    final wbRaw = json['worldBook'];
    final wsRaw = json['worldState'];
    return SaveSlot(
      id: (json['id'] ?? '').toString().isNotEmpty
          ? json['id'].toString()
          : newId(),
      title: (json['title'] ?? '未命名推演').toString(),
      worldBook: wbRaw is Map
          ? WorldBook.fromJson(Map<String, dynamic>.from(wbRaw))
          : WorldBook.blank(),
      history: (json['history'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => ChapterNode.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          <ChapterNode>[],
      chronicle: (json['chronicle'] ?? '').toString(),
      worldState: wsRaw is Map
          ? WorldState.fromJson(Map<String, dynamic>.from(wsRaw))
          : WorldState(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }

  /// 列表页用的摘要行。
  String get summaryLine {
    final parts = <String>[
      worldBook.name,
      '第 $chapterCount 幕',
      if (latestDate.isNotEmpty) latestDate,
    ];
    return parts.join(' · ');
  }
}
