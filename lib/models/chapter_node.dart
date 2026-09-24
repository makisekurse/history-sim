import 'annotation.dart';
import 'world_state.dart';

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

  /// 这一幕**结束后**的编年史快照。
  ///
  /// ⚠️ 回滚到第 N 幕时，编年史必须回到这一幕结束时的样子，
  /// 否则模型会「记得」那些已经被撤销的未来。旧存档该字段为空，
  /// 回滚时退回用顶层 chronicle（保守但不会串线）。
  final String? chronicleAfter;

  /// 这一幕**结束后**的世界状态快照。
  ///
  /// ⚠️ 每幕必须存一份 —— 只在存档顶层存一个「当前 state」是无法回滚到
  /// 任意历史幕的（顶层存的永远是最新的那份）。
  final WorldState? worldStateAfter;

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
    this.chronicleAfter,
    this.worldStateAfter,
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
        'chronicleAfter': chronicleAfter,
        'worldStateAfter': worldStateAfter?.toJson(),
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
        chronicleAfter: json['chronicleAfter']?.toString(),
        worldStateAfter: json['worldStateAfter'] is Map
            ? WorldState.fromJson(
                Map<String, dynamic>.from(json['worldStateAfter'] as Map),
              )
            : null,
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()),
      );

  ChapterNode copyWith({
    String? content,
    List<String>? choices,
    String? date,
    String? chronicleAfter,
    WorldState? worldStateAfter,
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
        chronicleAfter: chronicleAfter ?? this.chronicleAfter,
        worldStateAfter: worldStateAfter ?? this.worldStateAfter,
        timestamp: timestamp,
      );

  static String _capped(String s) =>
      s.length <= rawOutputLimit ? s : '${s.substring(0, rawOutputLimit)}\n…（已截断）';
}
