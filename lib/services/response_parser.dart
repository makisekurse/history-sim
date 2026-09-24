import '../models/annotation.dart';

/// 一幕输出的结构化解析结果。
class ParsedChapter {
  /// 去掉所有结构块之后的纯正文。
  final String body;

  /// 剧中日期（模型用 `<date>` 给出，可缺）。
  final String date;

  final List<String> choices;
  final List<GlossaryEntry> glossary;
  final List<CastEntry> cast;

  const ParsedChapter({
    required this.body,
    this.date = '',
    this.choices = const <String>[],
    this.glossary = const <GlossaryEntry>[],
    this.cast = const <CastEntry>[],
  });

  /// 分支够不够用 —— 不够就判定为「截断」，走兜底。
  bool get hasUsableChoices => choices.length >= 2;
}

/// 把模型的原始输出拆成正文 + 结构块。
///
/// 约定模型必须输出：
/// ```
/// <date>1949年11月30日</date>       （可选）
/// <choices>
/// 选项一
/// 选项二
/// </choices>
/// <glossary>
/// 词条|解释
/// </glossary>                        （可选）
/// <cast>
/// 姓名|身份|立场
/// </cast>                            （可选）
/// ```
class ResponseParser {
  ResponseParser._();

  static final RegExp _tagBlock = RegExp(
    r'<(date|choices|glossary|cast)>([\s\S]*?)</\1>',
    caseSensitive: false,
  );

  /// 流式过程中用来把还没闭合的标签块从预览里藏掉，
  /// 避免用户看到 `<choices>` 这种半截标签。
  static String stripForPreview(String raw) {
    var out = raw;
    // 完整块
    out = out.replaceAll(_tagBlock, '');
    // 未闭合的尾巴
    out = out.replaceAll(
      RegExp(r'<(date|choices|glossary|cast)>[\s\S]*$', caseSensitive: false),
      '',
    );
    return out.trimRight();
  }

  static ParsedChapter parse(String raw) {
    final choices = <String>[];
    final glossary = <GlossaryEntry>[];
    final cast = <CastEntry>[];
    String date = '';

    for (final m in _tagBlock.allMatches(raw)) {
      final tag = (m.group(1) ?? '').toLowerCase();
      final inner = m.group(2) ?? '';
      switch (tag) {
        case 'date':
          date = inner.trim();
          break;
        case 'choices':
          choices.addAll(_splitItems(inner, _cleanChoice));
          break;
        case 'glossary':
          glossary.addAll(
            _splitItems(inner, (l) => l)
                .map(GlossaryEntry.parseLine)
                .whereType<GlossaryEntry>(),
          );
          break;
        case 'cast':
          cast.addAll(
            _splitItems(inner, (l) => l)
                .map(CastEntry.parseLine)
                .whereType<CastEntry>(),
          );
          break;
      }
    }

    final body = raw.replaceAll(_tagBlock, '').trim();
    return ParsedChapter(
      body: body,
      date: date,
      choices: choices,
      glossary: glossary,
      cast: cast,
    );
  }

  /// 判断一段输出是不是「拒答」。
  ///
  /// 只看开头一小段，避免正文里提到"抱歉"被误判。
  static bool looksLikeRefusal(String raw) {
    final head = raw.trim();
    if (head.isEmpty) return true;
    final probe = head.length > 120 ? head.substring(0, 120) : head;
    const markers = <String>[
      '抱歉',
      '对不起',
      '无法协助',
      '无法提供',
      '不能提供',
      '不便讨论',
      '我无法',
      '我不能',
      '作为一个AI',
      '作为一个 AI',
      '作为人工智能',
      '涉及敏感',
      '违反相关规定',
      '不予生成',
      '换个话题',
    ];
    var hits = 0;
    for (final m in markers) {
      if (probe.contains(m)) hits++;
    }
    return hits >= 1 && head.length < 400;
  }

  static List<String> _splitItems(String block, String Function(String) clean) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map(clean)
        .where((l) => l.isNotEmpty)
        .toList();
    return lines;
  }

  /// 去掉「1. 」「- 」「选项一：」这类前缀。
  static String _cleanChoice(String line) => line
      .replaceAll(
        RegExp(r'^(\d+[\.、\s]|[-*•]\s*|选项[一二三四五六123456][：:\.、]?\s*)'),
        '',
      )
      .trim();
}
