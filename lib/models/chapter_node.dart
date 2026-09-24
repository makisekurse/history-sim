import 'annotation.dart';

/// 一幕推演节点。
///
/// 相比旧版新增 `date`（剧中日期）、`glossary`（随文注释）、`cast`（出场人物），
/// 后者支撑「长按看词条」与「人物志」两个功能。
class ChapterNode {
  final int chapterIndex;
  final String title;
  final String content;
  final String? playerAction;
  final String date;
  final List<String> choices;
  final List<GlossaryEntry> glossary;
  final List<CastEntry> cast;
  final DateTime timestamp;

  ChapterNode({
    required this.chapterIndex,
    required this.title,
    required this.content,
    this.playerAction,
    this.date = '',
    List<String>? choices,
    List<GlossaryEntry>? glossary,
    List<CastEntry>? cast,
    DateTime? timestamp,
  })  : choices = choices ?? <String>[],
        glossary = glossary ?? <GlossaryEntry>[],
        cast = cast ?? <CastEntry>[],
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chapterIndex': chapterIndex,
        'title': title,
        'content': content,
        'playerAction': playerAction,
        'date': date,
        'choices': choices,
        'glossary': glossary.map((e) => e.toJson()).toList(),
        'cast': cast.map((e) => e.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChapterNode.fromJson(Map<String, dynamic> json) => ChapterNode(
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 1,
        title: (json['title'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        playerAction: json['playerAction']?.toString(),
        date: (json['date'] ?? '').toString(),
        choices: (json['choices'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[],
        glossary: (json['glossary'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => GlossaryEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            <GlossaryEntry>[],
        cast: (json['cast'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => CastEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            <CastEntry>[],
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()),
      );

  ChapterNode copyWith({
    String? content,
    List<String>? choices,
    String? date,
  }) =>
      ChapterNode(
        chapterIndex: chapterIndex,
        title: title,
        content: content ?? this.content,
        playerAction: playerAction,
        date: date ?? this.date,
        choices: choices ?? this.choices,
        glossary: glossary,
        cast: cast,
        timestamp: timestamp,
      );
}
