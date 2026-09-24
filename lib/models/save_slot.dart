import 'chapter_node.dart';
import 'world_book.dart';

/// 一个存档槽 = 一本世界书 + 一串推演记录 + 滚动编年史摘要。
///
/// 存档里**内嵌世界书快照**，所以即使之后世界书被改或被删，
/// 老存档依然能完整打开。
class SaveSlot {
  final String id;
  String title;
  WorldBook worldBook;
  List<ChapterNode> history;

  /// 编年史滚动摘要：每若干幕压缩一次前情，塞进 system prompt，
  /// 解决「玩到第 20 幕模型已经忘了前面发生过什么」。
  String chronicle;

  DateTime createdAt;
  DateTime updatedAt;

  SaveSlot({
    required this.id,
    required this.title,
    required this.worldBook,
    List<ChapterNode>? history,
    this.chronicle = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : history = history ?? <ChapterNode>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  int get chapterCount => history.length;

  /// 最近一次落定的日期，用于列表页展示。
  String get latestDate =>
      history.isEmpty ? '' : history.last.date;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'worldBook': worldBook.toJson(),
        'history': history.map((e) => e.toJson()).toList(),
        'chronicle': chronicle,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SaveSlot.fromJson(Map<String, dynamic> json) {
    final wbRaw = json['worldBook'];
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
