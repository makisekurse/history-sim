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

  /// 模型生成的思维链 / 推演思考内容（`<think>` 或 `<thought>` 块）。
  final String thought;

  /// 模型返回的**原始文本**（未做任何清洗），仅用于排障。
  final String rawOutput;

  const ParsedChapter({
    required this.body,
    this.date = '',
    this.choices = const <String>[],
    this.glossary = const <GlossaryEntry>[],
    this.cast = const <CastEntry>[],
    this.stateRaw = '',
    this.thought = '',
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
/// 结构化提取（date / choices / glossary / cast / state / think）
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
    'think',
    'thought',
  ];

  static const String _tagAlt = '(date|choices|glossary|cast|state|think|thought)';

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
    var thought = '';

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
        case 'think':
        case 'thought':
          final t = b.inner.trim();
          if (t.isNotEmpty) {
            thought = thought.isEmpty ? t : '$thought\n\n$t';
          }
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
      thought: thought,
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

  /// 按位置剔除所有结构块跨度，其余原样保留。
  ///
  /// 做三件事：
  /// 1. **按位置**去掉结构块；
  /// 2. **逐行**去掉模板占位文字；
  /// 3. **智能清洗正文开头的模板标识前缀**（「正文：」「【正文】」「正文如下：」「（正文）」等）。
  /// 绝不按内容猜着删 —— 小说正文本身完全可能出现竖线、书名号，盲删会吃掉正文。
  static String _rebuildBody(String raw, List<_Block> blocks) {
    final text = _removeBlockSpans(raw, blocks);
    final cleaned = text
        .split('\n')
        .where((l) => !isBodyNoise(l))
        .join('\n')
        .trim();
    return cleanBodyPrefix(cleaned);
  }

  /// 正文开头残留的模板标识前缀（如「正文：」「【正文】」「正文如下：」「（正文）」「**正文**：」「### 正文」等）。
  static final RegExp _bodyPrefix = RegExp(
    r'^\s*(?:#{1,6}\s*)?'
    r'(?:\*\*)?'
    r'(?:[【\[（(]\s*正文(?:\s*内容|\s*如下|\s*开始|\s*部分)?\s*[】\]）)]'
    r'|正文\s*(?:如下|内容)\s*[:：]?'
    r'|正文\s*开始\s*[:：]'
    r'|正文(?=\s*[:：]|\s*\n|\s*\*\*))'
    r'(?:\*\*)?'
    r'\s*[:：]?'
    r'(?:\*\*)?'
    r'\s*',
  );

  /// 智能清洗正文开头的模板标识残留前缀，确保小说正文纯净。
  static String cleanBodyPrefix(String body) {
    var result = body.trim();
    while (_bodyPrefix.hasMatch(result)) {
      result = result.replaceFirst(_bodyPrefix, '').trim();
    }
    return result;
  }

  static String _removeBlockSpans(String raw, List<_Block> blocks) {
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

  // ---------- 模板占位文字兜底过滤 ----------
  //
  // 2026-09-25 实机事故：内核提示词给了可直接照抄的内容行，模型就把它们
  // 原样抄进了输出 —— 选项里混进「第一条可供主角决断的具体行动
  // （一句话，30~60 字）」，正文里混进「（正文：约 500 字的白描叙事）」。
  //
  // 内核已改成空骨架（见 PromptKernel.build）。这里是**第二道防线**：
  // 即使模型照抄了模板行，也进不了界面。

  /// 列表项（choices / glossary / cast）里的模板占位行。
  static final List<RegExp> _itemNoise = <RegExp>[
    RegExp(r'^第[一二三四五六七八九十]条\s*可供主角决断的具体行动.*$'),
    RegExp(r'^第[一二三四五六七八九十]条\s*[（(]\s*可选\s*[）)].*$'),
    RegExp(r'^第[一二三四五六七八九十]条\s*行动\s*$'),
    RegExp(r'^第[一二三四五六七八九十]条\s*$'),
    RegExp(r'^[（(]\s*可选\s*[）)]$'),
    RegExp(r'^生僻词条\s*\|.*解释.*$'),
    RegExp(r'^人物姓名\s*\|.*身份.*$'),
    RegExp(r'^词条\s*\|\s*一句话解释\s*$'),
    RegExp(r'^姓名\s*\|\s*身份\s*\|\s*立场\s*$'),
    RegExp(r'^[〈〈].*[〉〉]$'),
    // 天道敕令 / 主宰模式模板标识回响
    RegExp(r'^[【\[（(]\s*(?:天道敕令|主宰天道敕令).*$'),
  ];

  /// 正文里的模板占位行。
  ///
  /// 刻意比 [_itemNoise] **窄** —— 正文是文学文本，宁可漏杀也不能误杀。
  /// 例如 `〈…〉` 这种书名号在中文小说里是合法写法，所以不在这里过滤。
  static final List<RegExp> _bodyNoise = <RegExp>[
    // （正文：约 500 字的白描叙事）及其变体
    RegExp(r'^[（(]\s*正文\s*[:：].*[）)]$'),
    RegExp(r'^正文\s*[:：]\s*约?\s*\d*\s*字.*$'),
    // 剧中日期，例如 1949年11月30日
    RegExp(r'^剧中日期\s*[，,：:].*$'),
    RegExp(r'^第[一二三四五六七八九十]条\s*可供主角决断的具体行动.*$'),
    RegExp(r'^第[一二三四五六七八九十]条\s*[（(]\s*可选\s*[）)].*$'),
    // 天道敕令 / 主宰模式模板标识回响
    RegExp(r'^[【\[（(]\s*(?:天道敕令|主宰天道敕令).*$'),
    RegExp(r'^(?:天道敕令|主宰天道敕令)\s*[:：].*$'),
  ];

  /// 这一行是不是列表项里的模板占位文字。
  static bool isTemplateNoise(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('<!--') || t.endsWith('-->')) return true;
    for (final r in _itemNoise) {
      if (r.hasMatch(t)) return true;
    }
    return false;
  }

  /// 这一行是不是正文里的模板占位文字。
  static bool isBodyNoise(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('<!--') || t.endsWith('-->')) return true;
    for (final r in _bodyNoise) {
      if (r.hasMatch(t)) return true;
    }
    return false;
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
          // 兜底：模型可能把内核模板行原样抄进列表
          .where((l) => !isTemplateNoise(l))
          .map(clean)
          .where((l) => l.isNotEmpty)
          .where((l) => !isTemplateNoise(l))
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
