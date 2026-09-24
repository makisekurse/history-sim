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

  /// `<state>` 块的原文，交给 WorldState 服务去解析。
  final String stateRaw;

  /// 模型返回的**原始文本**（未做任何清洗），仅用于排障。
  final String rawOutput;

  const ParsedChapter({
    required this.body,
    this.date = '',
    this.choices = const <String>[],
    this.glossary = const <GlossaryEntry>[],
    this.cast = const <CastEntry>[],
    this.stateRaw = '',
    this.rawOutput = '',
  });

  /// 分支够不够用 —— 不够就判定为「截断」，走兜底。
  bool get hasUsableChoices => choices.length >= 2;
}

/// 模型输出解析器。
///
/// ## 为什么重写（2026-09-25）
///
/// 旧版只有一个严格正则 `<(tag)>...</\1>`，任何一点偏差（标签内空格、
/// 全角括号、中文书名号、缺闭合标签）都会让结构块**漏进正文** ——
/// 用户实机就看到过裸的 `<cast>` 块出现在小说正文里。
///
/// 新版改成四步流水线：
///
/// ```
/// 标签定位（宽容匹配各种变体）
///   ↓
/// 结构块切分（找不到闭合标签就吃到文末）
///   ↓
/// 结构化提取（date / choices / glossary / cast / state）
///   ↓
/// 正文重建（按位置剔除结构块跨度，其余原样保留）
/// ```
///
/// ⚠️ **不做过度清洗**：正文里出现的 `名字|身份|立场` 这类文本，
/// 只要不在结构块内就一律保留。绝不按内容猜着删 —— 小说正文本身
/// 完全可能出现竖线，盲删会吃掉正文。
class ResponseParser {
  ResponseParser._();

  static const List<String> knownTags = <String>[
    'date',
    'choices',
    'glossary',
    'cast',
    'state',
  ];

  static const String _tagAlt = '(date|choices|glossary|cast|state)';

  /// 宽容的开标签：`<cast>` `< cast >` `＜cast＞` `《cast》` `<Cast>`
  static final RegExp _openTag = RegExp(
    r'[<＜《]\s*' + _tagAlt + r'\s*[>＞》]',
    caseSensitive: false,
  );

  /// 宽容的闭标签：`</cast>` `</cast >` `＜/cast＞` `《/cast》` `</Cast>`
  static final RegExp _closeTag = RegExp(
    r'[<＜《]\s*/\s*' + _tagAlt + r'\s*[>＞》]',
    caseSensitive: false,
  );

  /// 完整解析。
  static ParsedChapter parse(String raw) {
    if (raw.trim().isEmpty) {
      return const ParsedChapter(body: '', rawOutput: '');
    }

    final blocks = _scanBlocks(raw);

    final choices = <String>[];
    final glossary = <GlossaryEntry>[];
    final cast = <CastEntry>[];
    var date = '';
    var stateRaw = '';

    for (final b in blocks) {
      switch (b.tag) {
        case 'date':
          date = b.inner.trim();
          break;
        case 'choices':
          choices.addAll(_splitItems(b.inner, _cleanChoice));
          break;
        case 'glossary':
          glossary.addAll(
            _splitItems(b.inner, (l) => l)
                .map(GlossaryEntry.parseLine)
                .whereType<GlossaryEntry>(),
          );
          break;
        case 'cast':
          cast.addAll(
            _splitItems(b.inner, (l) => l)
                .map(CastEntry.parseLine)
                .whereType<CastEntry>(),
          );
          break;
        case 'state':
          stateRaw = b.inner.trim();
          break;
      }
    }

    return ParsedChapter(
      body: _rebuildBody(raw, blocks),
      date: date,
      choices: choices,
      glossary: glossary,
      cast: cast,
      stateRaw: stateRaw,
      rawOutput: raw,
    );
  }

  /// 流式预览用：把结构块藏起来，避免用户看到半截标签。
  ///
  /// 与 [parse] 的区别：还没闭合的块也一并藏掉（吃到当前文本末尾），
  /// 并且额外处理**正在流入的半截标签**（`<`、`<ch`、`</cho`），
  /// 否则打字过程中会闪出 `<cho` 这种东西。
  static String stripForPreview(String raw) {
    if (raw.isEmpty) return '';
    var s = _rebuildBody(raw, _scanBlocks(raw)).trimRight();

    // 尾部可能是还没收完的标签前缀，一并藏掉
    final partial = RegExp(r'[<＜《][a-zA-Z/]{0,12}$').firstMatch(s);
    if (partial != null) {
      s = s.substring(0, partial.start).trimRight();
    }
    return s;
  }

  /// 扫描出所有结构块的位置与内容。
  static List<_Block> _scanBlocks(String raw) {
    final blocks = <_Block>[];
    var cursor = 0;

    while (cursor < raw.length) {
      final open = _openTag.firstMatch(raw.substring(cursor));
      if (open == null) break;

      final start = cursor + open.start;
      final tag = (open.group(1) ?? '').toLowerCase();
      final contentStart = cursor + open.end;

      // 找同名闭标签；找不到就吃到文末（未闭合块）
      var end = raw.length;
      var contentEnd = raw.length;
      final close = _findClose(raw, contentStart, tag);
      if (close != null) {
        end = close.end;
        contentEnd = close.start;
      }

      blocks.add(_Block(
        tag: tag,
        start: start,
        end: end,
        inner: raw.substring(contentStart, contentEnd),
      ));
      cursor = end;
    }
    return blocks;
  }

  static Match? _findClose(String raw, int from, String tag) {
    for (final m in _closeTag.allMatches(raw, from)) {
      if ((m.group(1) ?? '').toLowerCase() == tag) return m;
    }
    return null;
  }

  /// 按位置剔除所有结构块跨度，其余原样保留 —— 不做任何内容猜测式清洗。
  static String _rebuildBody(String raw, List<_Block> blocks) {
    if (blocks.isEmpty) return raw.trim();
    final sb = StringBuffer();
    var cursor = 0;
    for (final b in blocks) {
      if (b.start > cursor) sb.write(raw.substring(cursor, b.start));
      cursor = b.end;
    }
    if (cursor < raw.length) sb.write(raw.substring(cursor));
    return sb.toString().trim();
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

  static List<String> _splitItems(
    String block,
    String Function(String) clean,
  ) =>
      block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map(clean)
          .where((l) => l.isNotEmpty)
          .toList();

  /// 去掉「1. 」「- 」「选项一：」这类前缀。
  static String _cleanChoice(String line) => line
      .replaceAll(
        RegExp(r'^(\d+[\.、\s]|[-*•]\s*|选项[一二三四五六123456][：:\.、]?\s*)'),
        '',
      )
      .trim();
}

class _Block {
  final String tag;
  final int start;
  final int end;
  final String inner;

  const _Block({
    required this.tag,
    required this.start,
    required this.end,
    required this.inner,
  });
}
