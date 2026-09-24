import 'annotation.dart';

/// 一幕推演节点。
class ChapterNode {
  /// 模型原始输出保留上限（按字符计，约 30KB）。
  /// 异常模型输出不至于把存档无限撑大。
  static const int rawOutputLimit = 30000;

  final int chapterIndex;
  final String title;
  final String content;
  final String? playerAction;
  final String date;
  final List<String> choices;
  final List<GlossaryEntry> glossary;
  final List<CastEntry> cast;
  final DateTime timestamp;

  /// 模型返回的**原始文本**（未清洗），仅用于排障。
  ///
  /// 有了它，「为什么这次 cast 又漏了」可以直接翻出来看模型到底吐了什么，
  /// 不用再靠猜。只存本地，超过 [rawOutputLimit] 会被截断。
  final String rawOutput;

  ChapterNode({
    required this.chapterIndex,
    required this.title,
    required this.content,
    this.playerAction,
    this.date = '',
    List<String>? choices,
    List<GlossaryEntry>? glossary,
    List<CastEntry>? cast,
    this.rawOutput = '',
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
        'rawOutput': _capped(rawOutput),
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
        rawOutput: (json['rawOutput'] ?? '').toString(),
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
        rawOutput: rawOutput,
        timestamp: timestamp,
      );

  static String _capped(String s) =>
      s.length <= rawOutputLimit ? s : '${s.substring(0, rawOutputLimit)}\n…（已截断）';
}
