import '../../models/app_config.dart';
import '../../models/chapter_node.dart';
import '../../models/world_book.dart';

/// 内核层提示词 —— **编译进代码、用户不可修改**。
///
/// 它只负责一件事：保证输出格式契约成立。
/// 没有它，分支、词条、人物志全部解析不出来，游戏会散架。
class PromptKernel {
  PromptKernel._();

  static String build(AppConfig config) => '''
【输出契约 · 最高优先级，必须严格遵守】
每一幕的输出必须严格按下面的结构组织，标签名必须原样出现：

<date>剧中日期，例如 1949年11月30日</date>
（正文：约 ${config.maxWords} 字的白描叙事）

<choices>
第一条可供主角决断的具体行动（一句话，30~60 字）
第二条可供主角决断的具体行动
第三条（可选）
</choices>

<glossary>
生僻词条|一句话解释
</glossary>

<cast>
人物姓名|身份职务|当前立场
</cast>

硬性规则：
1. `<choices>` 必须出现，且内部至少 2 条、最多 3 条决断。
2. 每条决断必须是可立即执行的具体行动，不能是"继续观察""静观其变"这类空话。
3. `<glossary>` 与 `<cast>` 只列本幕**新出现**、读者可能不熟悉的项；没有就留空标签。
4. 正文中严禁出现"玩家""回合""经验值""存档""AI""模型""提示词""系统"等出戏词汇。
5. 严禁复述规则、严禁写"好的""以下是"这类过渡语，直接从叙事进入。
6. 除上述四个标签外，不要输出任何其他 XML/HTML 标签。''';
}

/// 框架层提示词 —— 提供一份默认值，**用户可以改，也可以一键恢复**。
class PromptFramework {
  PromptFramework._();

  static const String defaultText = '''
【创作定位】
这是一部基于公开史料的严肃历史文学作品，供创作者进行历史情境推演与人物心理刻画。
你是一位擅长宏大叙事的历史小说家，笔法取法中国古典史传与近代白描，重细节、重逻辑、重人性。

【叙事要求】
1. 立足史实框架：事件、地理、职官、器物、称谓均须符合该时代真实情况。
2. 白描为主，节奏沉稳有力；用具体场景、动作、对话推进，避免空泛议论。
3. 每个决断都要写出后果，且后果必须与决断构成因果关系，不能随机转折。
4. 尊重历史人物：写出其立场、顾虑与局限，不脸谱化、不戏说、不美化也不丑化。
5. 当情节触及需要审慎处理的历史内容时，以客观叙述方式呈现既有史实与多方立场，
   把笔墨放在人物的处境、抉择与治理难题上，而不作评价或渲染。
6. 每一幕结尾留下真实的张力与两难，不要草率收束。''';

  /// 用户改坏了也能一键回到这里。
  static const String retryNudges = '';
}

/// 把三层拼成最终 system prompt。
class PromptBuilder {
  PromptBuilder._();

  static String buildSystemPrompt({
    required AppConfig config,
    required WorldBook book,
    String frameworkOverride = '',
    String chronicle = '',
  }) {
    final framework =
        frameworkOverride.trim().isEmpty ? PromptFramework.defaultText : frameworkOverride.trim();

    final sb = StringBuffer();
    sb.writeln(PromptKernel.build(config));
    sb.writeln();
    sb.writeln(framework);
    sb.writeln();
    sb.writeln('【本局世界设定】');
    sb.writeln('世界书名：${book.name}');
    if (book.era.trim().isNotEmpty) {
      sb.writeln('时代与跨度：${book.era.trim()}');
    }
    sb.writeln('世界观与背景：${book.worldview.trim()}');
    sb.writeln('你（主角）扮演：${book.playerRole.trim()}');
    if (book.narrativeStyle.trim().isNotEmpty) {
      sb.writeln('叙事文风：${book.narrativeStyle.trim()}');
    }
    if (book.extraRules.trim().isNotEmpty) {
      sb.writeln('附加规则与禁忌：${book.extraRules.trim()}');
    }
    if (chronicle.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('【前情编年史（已发生的事实，必须保持一致）】');
      sb.writeln(chronicle.trim());
    }
    return sb.toString();
  }

  /// 滚动上下文：最近 [keepRecent] 幕。
  static List<Map<String, String>> buildMessages({
    required String systemPrompt,
    required List<ChapterNode> history,
    required String playerAction,
    int keepRecent = 3,
  }) {
    final messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': systemPrompt},
    ];

    final recent = history.length > keepRecent
        ? history.sublist(history.length - keepRecent)
        : history;

    for (final node in recent) {
      final act = node.playerAction;
      if (act != null && act.trim().isNotEmpty) {
        messages.add(<String, String>{
          'role': 'user',
          'content': '主角的决定：${act.trim()}',
        });
      }
      if (node.content.trim().isNotEmpty) {
        messages.add(<String, String>{
          'role': 'assistant',
          'content': node.content.trim(),
        });
      }
    }

    messages.add(<String, String>{
      'role': 'user',
      'content': playerAction.trim().isEmpty
          ? '请根据以上世界设定，写出第一幕：交代时间、地点与当前局势，'
              '点出主角面临的第一道难题，并按输出契约给出可供决断的分支。'
          : '面对当前局势，主角指示：“$playerAction”\n'
              '请据此推演接下来的局势演变，并按输出契约给出新一轮决断。',
    });
    return messages;
  }

  /// 检出拒答/截断后的「改写重试」补丁。
  ///
  /// 注意：这是**正向改写**，不是对抗性越狱词 ——
  /// 后者容易被平台风控判定为攻击，反而导致 Key 被限流。
  static String retryNudge(int attempt) {
    if (attempt <= 0) return '';
    if (attempt == 1) {
      return '\n\n【补充说明】上一条回复未能满足输出契约。'
          '请直接从剧情场景写起，不要在开头做任何说明或致歉；'
          '务必以 <choices> 标签给出 2~3 条具体决断。';
    }
    return '\n\n【再次说明】请以历史小说叙事的方式，'
        '聚焦人物的处境、抉择与治理难题，客观呈现多方立场与既有史实；'
        '不要评价、不要回避、不要解释。直接输出正文与 <choices> 结构块。';
  }
}
