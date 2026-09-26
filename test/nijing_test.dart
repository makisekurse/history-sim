import 'package:flutter_test/flutter_test.dart';
import 'package:nijing/models/annotation.dart';
import 'package:nijing/models/app_config.dart';
import 'package:nijing/models/chapter_node.dart';
import 'package:nijing/models/save_slot.dart';
import 'package:nijing/models/world_book.dart';
import 'package:nijing/models/world_line.dart';
import 'package:nijing/models/world_state.dart';
import 'package:nijing/services/game_session.dart';
import 'package:nijing/services/response_parser.dart';
import 'package:nijing/services/story_export_service.dart';
import 'package:nijing/services/text_layout.dart';
import 'package:nijing/services/wakelock_service.dart';
import 'package:nijing/services/world_state_service.dart';

void main() {
  group('WorldBook 导入', () {
    test('JSON 正常解析', () {
      final book = WorldBook.fromImportText('''
{"name":"测试世界","era":"1900","worldview":"背景","playerRole":"主角"}
''');
      expect(book.name, '测试世界');
      expect(book.era, '1900');
      expect(book.isPlayable, isTrue);
    });

    test('兼容别名键', () {
      final book = WorldBook.fromImportText('''
{"title":"别名世界","setting":"某背景","role":"某人物"}
''');
      expect(book.name, '别名世界');
      expect(book.worldview, '某背景');
      expect(book.playerRole, '某人物');
    });

    test('纯文本回落到世界观字段', () {
      final book = WorldBook.fromImportText('大唐开元年间，长安城。');
      expect(book.worldview, contains('大唐'));
      expect(book.isPlayable, isFalse);
      expect(book.missingFields, contains('扮演人物'));
    });

    test('导出再导入保持等价', () {
      final original = WorldBook(
        id: 'abc',
        name: '往返测试',
        worldview: '背景',
        playerRole: '主角',
        openingChoices: <String>['一', '二'],
      );
      final restored = WorldBook.fromImportText(original.exportToJson());
      expect(restored.name, original.name);
      expect(restored.openingChoices, original.openingChoices);
    });
  });

  group('ResponseParser · 标准与变体标签', () {
    const body = '他知道，从这一刻起，每一步都走在刀尖之上。';
    const choices =
        '<choices>\n1. 立即组建专项工作组\n2. 暂缓行动，暗中调查\n</choices>';
    const cast =
        '<cast>\n邓小平|中共中央副主席|主持日常工作\n王洪文|中共中央副主席|暗中阻挠\n</cast>';
    const glossary = '<glossary>\n绥靖公署|战时军政合一的区域性机构\n</glossary>';

    test('标准形态：正文干净，三块都抽走', () {
      final p = ResponseParser.parse('$body\n\n$choices\n\n$glossary\n\n$cast');
      expect(p.body, body);
      expect(p.choices.length, 2);
      expect(p.glossary.length, 1);
      expect(p.cast.length, 2);
      expect(p.hasUsableChoices, isTrue);
    });

    test('开标签带空格 < cast >', () {
      final p = ResponseParser.parse('$body\n\n< cast >\n邓小平|甲\n</cast>');
      expect(p.body, body);
      expect(p.cast.length, 1);
    });

    test('闭标签带空格 </cast >', () {
      final p = ResponseParser.parse('$body\n\n<cast>\n邓小平|甲\n</cast >');
      expect(p.body, body);
      expect(p.cast.length, 1);
    });

    test('全角尖括号 ＜cast＞', () {
      final p = ResponseParser.parse('$body\n\n＜cast＞\n邓小平|甲\n＜/cast＞');
      expect(p.body, body);
      expect(p.cast.length, 1);
    });

    test('中文书名号《cast》', () {
      final p = ResponseParser.parse('$body\n\n《cast》\n邓小平|甲\n《/cast》');
      expect(p.body, body);
      expect(p.cast.length, 1);
    });

    test('标签大小写混用 <Cast>…</CAST>', () {
      final p = ResponseParser.parse('$body\n\n<Cast>\n邓小平|甲\n</CAST>');
      expect(p.body, body);
      expect(p.cast.length, 1);
    });

    test('未闭合块：从开标签吃到文末', () {
      final p = ResponseParser.parse('$body\n\n<cast>\n邓小平|甲\n李先念|乙');
      expect(p.body, body);
      expect(p.cast.length, 2);
    });

    test('第二个块未闭合，不影响前面的提取', () {
      final p = ResponseParser.parse('$body\n\n$choices\n\n<cast>\n邓小平|甲');
      expect(p.body, body);
      expect(p.choices.length, 2);
      expect(p.cast.length, 1);
    });

    test('空结构块', () {
      final p = ResponseParser.parse('$body\n\n<cast>\n</cast>\n\n$choices');
      expect(p.body, body);
      expect(p.cast, isEmpty);
      expect(p.choices.length, 2);
    });

    test('块在正文之前', () {
      final p = ResponseParser.parse('$cast\n\n$body\n\n$choices');
      expect(p.body, body);
      expect(p.cast.length, 2);
      expect(p.choices.length, 2);
    });

    test('多个同名块合并', () {
      final p = ResponseParser.parse(
        '$body\n\n<cast>\n邓小平|甲\n</cast>\n\n<cast>\n李先念|乙\n</cast>',
      );
      expect(p.body, body);
      expect(p.cast.length, 2);
    });

    test('截断输出：有正文无 choices', () {
      final p = ResponseParser.parse('$body\n\n<choices>\n1. 只有一条');
      expect(p.body, body);
      expect(p.hasUsableChoices, isFalse);
    });

    test('date 与 state 也能抽走', () {
      final p = ResponseParser.parse(
        '<date>1949年11月30日</date>\n$body\n\n<state>\ntime: 夜\n</state>',
      );
      expect(p.date, '1949年11月30日');
      expect(p.stateRaw, contains('time'));
      expect(p.body, body);
    });

    test('rawOutput 保存原始文本', () {
      final raw = '$body\n\n$cast';
      final p = ResponseParser.parse(raw);
      expect(p.rawOutput, raw);
    });
  });

  group('ResponseParser · 不做过度清洗（关键回归）', () {
    test('正文里的竖线行必须原样保留', () {
      const raw = '他翻开名册，上面写着：\n\n张三|县令|谨慎\n李四|主簿|亲善\n\n'
          '这行字让他久久没有说话。';
      final p = ResponseParser.parse(raw);
      expect(p.body, contains('张三|县令|谨慎'));
      expect(p.body, contains('李四|主簿|亲善'));
      expect(p.cast, isEmpty);
    });

    test('正文里出现尖括号但不构成标签时保留', () {
      const raw = '他写道：「此事<不可说>，慎之。」';
      final p = ResponseParser.parse(raw);
      expect(p.body, contains('<不可说>'));
    });

    test('结构块被剔除后，前后正文都还在', () {
      final p = ResponseParser.parse(
        '前半段正文。\n\n<cast>\n甲|乙\n</cast>\n\n后半段正文。',
      );
      expect(p.body, contains('前半段正文。'));
      expect(p.body, contains('后半段正文。'));
      expect(p.body.contains('cast'), isFalse);
    });
  });

  group('ResponseParser · 流式预览', () {
    test('未闭合标签在预览里也要藏掉', () {
      final preview =
          ResponseParser.stripForPreview('正文开始…\n\n<choices>\n第一条');
      expect(preview.contains('<choices>'), isFalse);
      expect(preview.contains('正文开始'), isTrue);
    });

    test('正在流入的半截标签不闪出', () {
      final preview = ResponseParser.stripForPreview('正文开始…\n\n<ca');
      expect(preview.contains('<ca'), isFalse);
      expect(preview.contains('正文开始'), isTrue);
    });

    test('拒答识别', () {
      expect(ResponseParser.looksLikeRefusal('抱歉，我无法协助这个请求。'), isTrue);
      expect(ResponseParser.looksLikeRefusal(''), isTrue);
      expect(
        ResponseParser.looksLikeRefusal('1949年10月，常德前线司令部里灯火通明。'),
        isFalse,
      );
    });
  });

  group('Annotation', () {
    test('词条行解析', () {
      final e = GlossaryEntry.parseLine('绥靖公署|战时设立的军政合一的区域性机构');
      expect(e, isNotNull);
      expect(e!.term, '绥靖公署');
    });

    test('非法行返回 null', () {
      expect(GlossaryEntry.parseLine('没有分隔符'), isNull);
    });

    test('人物合并不覆盖成空', () {
      const a = CastEntry(name: '刘伯承', role: '司令员', stance: '支持');
      const b = CastEntry(name: '刘伯承', role: '', stance: '观望');
      final merged = a.merge(b);
      expect(merged.role, '司令员');
      expect(merged.stance, '观望');
    });
  });

  group('WorldStateService · 解析', () {
    test('标准格式', () {
      final s = WorldStateService.parse('''
时间：1949年11月23日 深夜
地点：重庆市委机关
事实：城东发生武装冲突；张某已经知道玩家在查资金
关系：张某|谨慎；李某|信任
事件：银行挤兑仍在持续；地方武装问题尚未解决
''');
      expect(s.time, '1949年11月23日 深夜');
      expect(s.location, '重庆市委机关');
      expect(s.facts.length, 2);
      expect(s.relations['张某'], '谨慎');
      expect(s.relations['李某'], '信任');
      expect(s.events.length, 2);
    });

    test('容错：半角冒号 / 半角分号 / 英文键名 / 多余空行', () {
      final s = WorldStateService.parse('''

time: 1949年11月
location: 重庆

facts: 甲; 乙

''');
      expect(s.time, '1949年11月');
      expect(s.location, '重庆');
      expect(s.facts, <String>['甲', '乙']);
    });

    test('容错：键名带星号与序号前缀', () {
      final s = WorldStateService.parse('**时间**：夜\n1. 地点：山城');
      expect(s.time, '夜');
      expect(s.location, '山城');
    });

    test('畸形输入不抛异常，返回空 state', () {
      expect(WorldStateService.parse('').isEmpty, isTrue);
      expect(WorldStateService.parse('乱七八糟没有冒号').isEmpty, isTrue);
      expect(WorldStateService.parse('未知键：值').isEmpty, isTrue);
    });
  });

  group('WorldStateService · 合并', () {
    test('时间地点覆盖，事实整体替换', () {
      final prev = WorldState(
        time: '旧时间',
        location: '旧地点',
        facts: <String>['旧事实'],
      );
      final next = WorldStateService.merge(
        prev,
        WorldState(time: '新时间', facts: <String>['新事实']),
      );
      expect(next.time, '新时间');
      expect(next.location, '旧地点'); // 新值为空则不覆盖
      expect(next.facts, <String>['新事实']);
    });

    test('关系是增量：模型没提到的旧关系保留', () {
      final prev = WorldState(relations: <String, String>{'张某': '谨慎'});
      final next = WorldStateService.merge(
        prev,
        WorldState(relations: <String, String>{'李某': '信任'}),
      );
      expect(next.relations['张某'], '谨慎');
      expect(next.relations['李某'], '信任');
    });

    test('关系同键时新值覆盖', () {
      final prev = WorldState(relations: <String, String>{'张某': '谨慎'});
      final next = WorldStateService.merge(
        prev,
        WorldState(relations: <String, String>{'张某': '敌视'}),
      );
      expect(next.relations['张某'], '敌视');
    });

    test('不修改传入的旧状态（避免快照被就地改坏）', () {
      final prev = WorldState(facts: <String>['甲']);
      WorldStateService.merge(prev, WorldState(facts: <String>['乙']));
      expect(prev.facts, <String>['甲']);
    });
  });

  group('WorldStateService · 上限与截断', () {
    test('事实超过 12 条时截断', () {
      final s = WorldState(
        facts: List<String>.generate(20, (i) => '事实$i'),
      );
      final capped = WorldStateService.merge(s, WorldState());
      expect(capped.facts.length, WorldState.maxFacts);
    });

    test('事件超过 8 条时截断', () {
      final s = WorldState(
        events: List<String>.generate(15, (i) => '事件$i'),
      );
      final capped = WorldStateService.merge(s, WorldState());
      expect(capped.events.length, WorldState.maxEvents);
    });

    test('单条超长被截断并加省略号', () {
      final long = '甲' * 300;
      final s = WorldStateService.merge(
        WorldState(),
        WorldState(facts: <String>[long]),
      );
      expect(s.facts.first.length, lessThanOrEqualTo(WorldState.maxItemChars + 1));
      expect(s.facts.first.endsWith('…'), isTrue);
    });

    test('重复条目去重', () {
      final s = WorldStateService.merge(
        WorldState(),
        WorldState(facts: <String>['甲', '甲', '乙']),
      );
      expect(s.facts, <String>['甲', '乙']);
    });

    test('总预算兜底：超长时从尾部丢弃', () {
      final s = WorldState(
        facts: List<String>.generate(12, (i) => '甲' * 120),
        events: List<String>.generate(8, (i) => '乙' * 120),
      );
      final capped = WorldStateService.merge(s, WorldState());
      final total = capped.facts.fold<int>(0, (a, e) => a + e.length) +
          capped.events.fold<int>(0, (a, e) => a + e.length);
      expect(total, lessThanOrEqualTo(WorldState.maxTotalChars));
    });
  });

  group('WorldStateService · 渲染', () {
    test('渲染进 prompt', () {
      final s = WorldState(
        time: '夜',
        location: '山城',
        facts: <String>['甲'],
        relations: <String, String>{'张': '谨慎'},
        events: <String>['乙'],
      );
      final text = WorldStateService.renderForPrompt(s);
      expect(text, contains('时间：夜'));
      expect(text, contains('地点：山城'));
      expect(text, contains('已知事实：甲'));
      expect(text, contains('人物关系：张|谨慎'));
      expect(text, contains('进行中事件：乙'));
    });

    test('空状态渲染为空串', () {
      expect(WorldStateService.renderForPrompt(WorldState()), '');
    });

    test('inlineSummary 给游玩页顶部用', () {
      final s = WorldState(time: '1949年11月23日', location: '重庆');
      expect(s.inlineSummary, '重庆 · 1949年11月23日');
    });
  });

  group('WorldState · 序列化', () {
    test('往返等价', () {
      final s = WorldState(
        time: '夜',
        location: '山城',
        facts: <String>['甲'],
        relations: <String, String>{'张': '谨慎'},
        events: <String>['乙'],
      );
      final restored = WorldState.fromJson(s.toJson());
      expect(restored.time, s.time);
      expect(restored.facts, s.facts);
      expect(restored.relations, s.relations);
      expect(restored.events, s.events);
    });

    test('copy 是深拷贝', () {
      final s = WorldState(facts: <String>['甲']);
      final c = s.copy();
      c.facts.add('乙');
      expect(s.facts.length, 1);
    });
  });

  group('GameSession · 世界线分支与切换', () {
    SaveSlot newSlot() => SaveSlot(
          id: 's1',
          title: '测试局',
          worldBook: WorldBook(
            id: 'b1',
            name: '测试世界',
            worldview: '背景',
            playerRole: '主角',
          ),
        );

    void addChapter(GameSession s, String tag, String stateRaw) {
      s.appendChapter(
        content: '正文-$tag',
        playerAction: '行动-$tag',
        date: '第$tag天',
        choices: <String>['选项A-$tag', '选项B-$tag'],
        glossary: const <GlossaryEntry>[],
        cast: const <CastEntry>[],
        rawOutput: 'raw-$tag',
        stateRaw: stateRaw,
      );
    }

    /// 造一个三幕的局。
    GameSession threeChapters() {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天\n地点：甲地');
      addChapter(s, '二', '时间：第二天\n地点：乙地');
      addChapter(s, '三', '时间：第三天\n地点：丙地');
      return s;
    }

    test('appendChapter 写入状态快照', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天\n地点：甲地');
      expect(s.chapterCount, 1);
      expect(s.worldState.time, '第一天');
      expect(s.history.last.worldStateAfter?.time, '第一天');
      expect(s.history.last.worldStateAfter?.location, '甲地');
    });

    test('新局默认只有一条主线', () {
      final s = GameSession(newSlot());
      expect(s.lines.length, 1);
      expect(s.line.isBranch, isFalse);
      expect(s.line.name, '主线');
    });

    // ---------- 分岔（核心） ----------

    test('分岔：新线保留到分岔点，状态等于那一幕的快照', () {
      final s = threeChapters();
      final branch = s.branchFrom(0); // 从第 1 幕分岔

      expect(branch.chapterCount, 1);
      expect(branch.branchedAtChapter, 1);
      expect(branch.isBranch, isTrue);
      // 状态必须回到第 1 幕结束时，不能还停在第 3 幕
      expect(branch.worldState.time, '第一天');
      expect(branch.worldState.location, '甲地');
      // 分岔后自动切到新线
      expect(s.line.id, branch.id);
      expect(s.chapterCount, 1);
    });

    test('分岔：原线完全不动（关键回归）', () {
      final s = threeChapters();
      final mainId = s.line.id;
      s.branchFrom(0);

      final main = s.lines.firstWhere((l) => l.id == mainId);
      expect(main.chapterCount, 3);
      expect(main.worldState.time, '第三天');
      expect(main.history.last.content, '正文-三');
    });

    test('分岔：从中间幕分', () {
      final s = threeChapters();
      final branch = s.branchFrom(1); // 从第 2 幕分岔
      expect(branch.chapterCount, 2);
      expect(branch.branchedAtChapter, 2);
      expect(branch.worldState.time, '第二天');
    });

    test('两条线互不干扰：一边继续推演，另一边不受影响', () {
      final s = threeChapters();
      final mainId = s.line.id;
      s.branchFrom(0); // 切到新线（只有 1 幕）

      addChapter(s, '甲', '时间：第九天\n地点：丁地');

      expect(s.chapterCount, 2);
      expect(s.worldState.time, '第九天');

      final main = s.lines.firstWhere((l) => l.id == mainId);
      expect(main.chapterCount, 3);
      expect(main.worldState.time, '第三天');
    });

    test('两条线的选择记录互相独立', () {
      final s = threeChapters();
      final mainId = s.line.id;
      s.branchFrom(0);
      addChapter(s, '甲', '时间：第九天');

      // 新线的可选行动来自新线自己的最后一幕
      expect(s.choices.first, '选项A-甲');

      s.switchLine(mainId);
      expect(s.choices.first, '选项A-三');
    });

    // ---------- 切换 ----------

    test('切换世界线：正文/状态/编年史/选项全部跟着换', () {
      final s = threeChapters();
      final mainId = s.line.id;
      s.attachChronicle('主线编年史');
      s.branchFrom(0);

      // 当前在新线
      expect(s.chapterCount, 1);
      s.attachChronicle('分支编年史');
      expect(s.chronicle, '分支编年史');

      // 切回主线
      s.switchLine(mainId);
      expect(s.chapterCount, 3);
      expect(s.chronicle, '主线编年史');
      expect(s.worldState.time, '第三天');
      expect(s.choices.first, '选项A-三');
    });

    test('切换后 worldState 是那条线自己的，不是共享引用', () {
      final s = threeChapters();
      final mainId = s.line.id;
      s.branchFrom(0);
      addChapter(s, '甲', '时间：第九天\n关系：李某|投诚');

      s.switchLine(mainId);
      // 主线不该看到分支里新增的关系
      expect(s.worldState.relations.containsKey('李某'), isFalse);
      expect(s.worldState.time, '第三天');
    });

    // ---------- 在分岔点重生成 ----------

    test('在分岔点重生成：状态退回 baseState 而不是清空（关键回归）', () {
      final s = threeChapters();
      s.branchFrom(1); // 新线保留 2 幕，baseState = 第 1 幕结束时
      expect(s.worldState.time, '第二天');

      s.popLastForReroll(); // 重生成第 2 幕
      // 必须退到「第 1 幕结束时」，不能变成空 ——
      // 否则这条线会丢掉分岔时继承来的全部局势
      expect(s.chapterCount, 1);
      expect(s.worldState.time, '第一天');
      expect(s.worldState.location, '甲地');
    });

    // ---------- 删除 / 重命名 ----------

    test('删除世界线', () {
      final s = threeChapters();
      final mainId = s.line.id;
      final branch = s.branchFrom(0);
      expect(s.lines.length, 2);

      expect(s.deleteLine(branch.id), isTrue);
      expect(s.lines.length, 1);
      // 删掉当前线后自动切到剩下那条
      expect(s.line.id, mainId);
      expect(s.chapterCount, 3);
    });

    test('最后一条世界线删不掉', () {
      final s = threeChapters();
      expect(s.deleteLine(s.line.id), isFalse);
      expect(s.lines.length, 1);
    });

    test('重命名世界线', () {
      final s = threeChapters();
      final branch = s.branchFrom(0);
      s.renameLine(branch.id, '走西南路线');
      expect(s.line.name, '走西南路线');
      // 空白名不生效
      s.renameLine(branch.id, '   ');
      expect(s.line.name, '走西南路线');
    });

    test('分岔名不重复', () {
      final s = threeChapters();
      s.branchFrom(0);
      final n1 = s.line.name;
      s.branchFrom(0);
      expect(s.line.name, isNot(n1));
    });

    // ---------- 快照自愈 ----------

    test('旧存档缺快照：从第一幕分岔也能拿到正确的空状态', () {
      // 模拟「世界书自带开篇」：第一幕是 UI 层直接造的，没有快照
      final slot = newSlot();
      slot.activeLine.history = <ChapterNode>[
        ChapterNode(
          chapterIndex: 1,
          title: '第一幕',
          content: '开场',
          choices: <String>['a', 'b'],
        ),
      ];
      final s = GameSession(slot); // 构造时自愈
      expect(s.history.first.worldStateAfter, isNotNull);

      final branch = s.branchFrom(0);
      expect(branch.worldState.isEmpty, isTrue);
      expect(branch.chronicle, '');
    });

    test('自愈后每一幕都有快照', () {
      final slot = newSlot();
      slot.activeLine.history = <ChapterNode>[
        ChapterNode(
          chapterIndex: 1,
          title: '一',
          content: '正文',
          choices: <String>['a', 'b'],
        ),
        ChapterNode(
          chapterIndex: 2,
          title: '二',
          content: '正文',
          choices: <String>['c', 'd'],
        ),
      ];
      GameSession(slot);
      for (final n in slot.activeLine.history) {
        expect(n.worldStateAfter, isNotNull);
        expect(n.chronicleAfter, isNotNull);
      }
    });

    // ---------- reroll / 编年史 / 开局 ----------

    test('reroll 不继承上一次留下的状态', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      addChapter(s, '二', '时间：第二天\n关系：张某|已死');
      expect(s.worldState.relations['张某'], '已死');

      s.popLastForReroll();
      expect(s.worldState.time, '第一天');
      expect(s.worldState.relations.containsKey('张某'), isFalse);
      expect(s.chapterCount, 1);
    });

    test('reroll 到开局时状态与编年史清空', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      s.attachChronicle('编年史');
      s.popLastForReroll();
      expect(s.chapterCount, 0);
      expect(s.worldState.isEmpty, isTrue);
      expect(s.chronicle, '');
      expect(s.choices, isEmpty);
    });

    test('attachChronicle 只记到最后一幕快照上', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      addChapter(s, '二', '时间：第二天');
      s.attachChronicle('新编年史');
      expect(s.history.last.chronicleAfter, '新编年史');
      expect(s.history.first.chronicleAfter, '');
    });

    test('seedOpening 直接落第一幕且带快照', () {
      final s = GameSession(newSlot());
      s.seedOpening(
        content: '开场',
        date: '第一天',
        choices: <String>['x', 'y'],
      );
      expect(s.chapterCount, 1);
      expect(s.choices, <String>['x', 'y']);
      expect(s.history.first.worldStateAfter, isNotNull);
      expect(s.history.first.chronicleAfter, '');
    });

    test('toSlot 把状态写回存档', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      final slot = s.toSlot();
      expect(slot.history.length, 1);
      expect(slot.worldState.time, '第一天');
    });
  });

  group('存档槽 · 世界线序列化与旧档迁移', () {
    SaveSlot base() => SaveSlot(
          id: 's1',
          title: '测试局',
          worldBook: WorldBook(id: 'b1', name: '测试世界'),
        );

    test('新档默认带一条主线', () {
      final slot = base();
      expect(slot.lines.length, 1);
      expect(slot.activeLineId, slot.lines.first.id);
    });

    test('多条世界线往返 JSON 不丢', () {
      final slot = base();
      final s = GameSession(slot);
      s.appendChapter(
        content: '正文',
        playerAction: '行动',
        date: '第一天',
        choices: <String>['a', 'b'],
        glossary: const <GlossaryEntry>[],
        cast: const <CastEntry>[],
        rawOutput: '',
        stateRaw: '时间：第一天',
      );
      s.branchFrom(0);

      final restored = SaveSlot.fromJson(slot.toJson());
      expect(restored.lines.length, 2);
      expect(restored.activeLineId, slot.activeLineId);
      expect(restored.activeLine.isBranch, isTrue);
      expect(restored.activeLine.parentLineId, slot.lines.first.id);
    });

    test('activeLineId 指向不存在的线时自动兜到第一条', () {
      final slot = SaveSlot(
        id: 's1',
        title: 't',
        worldBook: WorldBook(id: 'b', name: 'w'),
        activeLineId: '不存在',
      );
      expect(slot.activeLineId, slot.lines.first.id);
    });

    test('旧存档（v1）迁移：顶层三件套包成主线', () {
      // v1 存档长这样：history / chronicle / worldState 全在顶层，没有 lines
      final legacy = <String, dynamic>{
        'id': 'old1',
        'title': '旧档',
        'worldBook': WorldBook(id: 'b1', name: '旧世界').toJson(),
        'history': <Map<String, dynamic>>[
          ChapterNode(
            chapterIndex: 1,
            title: '第一幕',
            content: '旧正文',
            choices: <String>['x'],
          ).toJson(),
        ],
        'chronicle': '旧编年史',
        'worldState': WorldState(time: '旧时间').toJson(),
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
      };

      final slot = SaveSlot.fromJson(legacy);
      expect(slot.lines.length, 1);
      expect(slot.activeLine.name, '主线');
      expect(slot.chapterCount, 1);
      expect(slot.history.first.content, '旧正文');
      expect(slot.chronicle, '旧编年史');
      expect(slot.worldState.time, '旧时间');
    });

    test('摘要行会带上世界线数量', () {
      final slot = base();
      GameSession(slot).appendChapter(
        content: '正文',
        playerAction: '行动',
        date: '',
        choices: <String>['a', 'b'],
        glossary: const <GlossaryEntry>[],
        cast: const <CastEntry>[],
        rawOutput: '',
        stateRaw: '',
      );
      expect(slot.summaryLine.contains('世界线'), isFalse);
      GameSession(slot).branchFrom(0);
      expect(slot.summaryLine.contains('2 条世界线'), isTrue);
    });
  });

  group('存档槽 · 回滚备份识别', () {
    // 2026-09-25 实机问题：回滚自动生成的备份混在正常列表里，
    // 用户只玩到第二幕却看到三个「推演」。

    test('备份 id 带前缀，能被识别', () {
      final id = SaveSlot.backupIdFor('abc123');
      expect(id, 'backup_abc123');
      final slot = SaveSlot(
        id: id,
        title: '【回滚备份】某局',
        worldBook: WorldBook(id: 'b', name: '世界'),
      );
      expect(slot.isBackup, isTrue);
    });

    test('普通存档不算备份', () {
      final slot = SaveSlot(
        id: 'abc123',
        title: '某局',
        worldBook: WorldBook(id: 'b', name: '世界'),
      );
      expect(slot.isBackup, isFalse);
    });

    test('备份标记能穿过 JSON 往返', () {
      final slot = SaveSlot(
        id: SaveSlot.backupIdFor('xyz'),
        title: '备份',
        worldBook: WorldBook(id: 'b', name: '世界'),
      );
      final restored = SaveSlot.fromJson(slot.toJson());
      expect(restored.isBackup, isTrue);
    });
  });

  group('TextLayout · 正文分段与缩进', () {
    // 2026-09-25：「首行缩进」开关加了没效果，根因就在分段 ——
    // 旧代码只按 `\n\n` 切段，模型经常用单个 `\n`，整篇被当成一个段落，
    // 只在最开头缩进一次，看起来就像没生效。

    test('单个换行也能切段', () {
      expect(TextLayout.paragraphs('第一段\n第二段\n第三段'),
          <String>['第一段', '第二段', '第三段']);
    });

    test('空行切段', () {
      expect(TextLayout.paragraphs('第一段\n\n第二段'),
          <String>['第一段', '第二段']);
    });

    test('CRLF 也能切', () {
      expect(TextLayout.paragraphs('第一段\r\n第二段'),
          <String>['第一段', '第二段']);
    });

    test('连续空行不会产生空段落', () {
      expect(TextLayout.paragraphs('甲\n\n\n\n乙\n   \n丙'),
          <String>['甲', '乙', '丙']);
    });

    test('缩进用全角空格', () {
      expect(TextLayout.indent(2), '　　');
      expect(TextLayout.indent(2).length, 2);
      expect(TextLayout.indent(0), '');
    });

    test('缩进越界会被夹住', () {
      expect(TextLayout.indent(-3), '');
      expect(TextLayout.indent(99).length, 4);
    });

    test('段间距三档', () {
      expect(TextLayout.spacing('tight'), lessThan(TextLayout.spacing('normal')));
      expect(TextLayout.spacing('loose'), greaterThan(TextLayout.spacing('normal')));
      expect(TextLayout.spacing('未知值'), TextLayout.spacing('normal'));
    });
  });

  group('ResponseParser · 模板占位文字过滤', () {
    // 2026-09-25 实机事故：内核提示词给了可直接照抄的内容行，模型把它们
    // 原样抄进了输出。用户截图里选项混着「第一条可供主角决断的具体行动
    // （一句话，30~60 字）」，正文混着「（正文：约 500 字的白描叙事）」。
    // 内核已改空骨架，这里是第二道防线的回归。

    test('选项里的模板行被剔除', () {
      const raw = '''
<date>1976年9月28日</date>
夜色如墨，一辆不起眼的黑色轿车悄然驶离西山。

<choices>
第一条可供主角决断的具体行动（一句话，30~60 字）
向叶帅提议立即起草政治定性文件，为行动提供法理依据。
第二条可供主角决断的具体行动
要求汪东兴派遣可信人员秘密前往上海，监控通讯线路。
第三条（可选）
决定暂不通知华国锋具体抓捕时间，仅要求其签署调令。
</choices>
''';
      final p = ResponseParser.parse(raw);
      expect(p.choices.length, 3);
      for (final c in p.choices) {
        expect(c.contains('可供主角决断的具体行动'), isFalse);
        expect(c.contains('可选'), isFalse);
      }
      expect(p.choices.first.startsWith('向叶帅提议'), isTrue);
      expect(p.choices.last.startsWith('决定暂不通知'), isTrue);
    });

    test('正文里的模板行被剔除', () {
      const raw = '''
<date>1976年9月28日</date>
（正文：约 500 字的白描叙事）
夜色如墨，一辆不起眼的黑色轿车悄然驶离西山。

<choices>
甲
乙
</choices>
''';
      final p = ResponseParser.parse(raw);
      expect(p.body.contains('白描叙事'), isFalse);
      expect(p.body.startsWith('夜色如墨'), isTrue);
    });

    test('正文里的合法书名号不会被误删', () {
      const raw = '''
<date>某日</date>
他翻开《史记》，又想起〈滕王阁序〉里的句子。

<choices>
甲
乙
</choices>
''';
      final p = ResponseParser.parse(raw);
      expect(p.body.contains('滕王阁序'), isTrue);
    });

    test('判定函数', () {
      expect(
        ResponseParser.isTemplateNoise('第一条可供主角决断的具体行动'),
        isTrue,
      );
      expect(ResponseParser.isTemplateNoise('第三条（可选）'), isTrue);
      expect(ResponseParser.isTemplateNoise('向叶帅提议起草文件'), isFalse);
      expect(
        ResponseParser.isBodyNoise('（正文：约 500 字的白描叙事）'),
        isTrue,
      );
      expect(ResponseParser.isBodyNoise('夜色如墨'), isFalse);
    });

    test('状态块里的模板占位值被剔除', () {
      final s = WorldStateService.parse('''
时间：此刻的剧中时间
地点：主角此刻所在
事实：条目；条目（最多 12 条，按重要性从高到低）
关系：姓名|此刻态度
事件：进行中的事件
''');
      expect(s.time, '');
      expect(s.location, '');
      expect(s.facts, isEmpty);
      expect(s.relations, isEmpty);
      expect(s.events, isEmpty);
    });
  });

  group('ResponseParser · think 与 thought 思维链隔离与提取', () {
    test('标准 <think> 标签抽取思考并保持正文纯净', () {
      const raw = '''
<think>
当前局势危急，需要权衡利弊。
决定让主角前往茶馆接头。
</think>

<date>1949年11月1日</date>

秋风肃杀，林怀民裹紧了大衣，快步走向转角的茶馆。

<choices>
1. 推门而入
2. 在门外稍作观察
</choices>
''';
      final p = ResponseParser.parse(raw);
      expect(p.thought, contains('当前局势危急'));
      expect(p.thought, contains('决定让主角前往茶馆接头'));
      expect(p.body, contains('秋风肃杀'));
      expect(p.body, isNot(contains('<think>')));
      expect(p.body, isNot(contains('当前局势危急')));
      expect(p.date, '1949年11月1日');
      expect(p.choices.length, 2);
    });

    test('变体 <thought> 标签也能正常识别', () {
      const raw = '''
<thought>
深入分析各方势力。
</thought>
夜色渐深，灯火阑珊。
<choices>
1. 歇息
2. 巡视
</choices>
''';
      final p = ResponseParser.parse(raw);
      expect(p.thought, '深入分析各方势力。');
      expect(p.body, '夜色渐深，灯火阑珊。');
      expect(p.body, isNot(contains('深入分析')));
    });

    test('未闭合的 <think> 在流式预览中隐藏', () {
      const raw = '''
天色微明。
<think>
正在推演下一步逻辑，尚未结束…
''';
      final preview = ResponseParser.stripForPreview(raw);
      expect(preview, '天色微明。');
      expect(preview, isNot(contains('正在推演')));
    });

    test('流式中正在流入的半截 think 标签不闪烁', () {
      expect(ResponseParser.stripForPreview('晨光初照。<th'), '晨光初照。');
      expect(ResponseParser.stripForPreview('晨光初照。<think'), '晨光初照。');
      expect(ResponseParser.stripForPreview('晨光初照。</think'), '晨光初照。');
    });
  });

  group('ChapterNode · thought 思维链字段与序列化', () {
    test('JSON 序列化往返保留 thought', () {
      final node = ChapterNode(
        chapterIndex: 1,
        title: '第一幕',
        content: '正文内容',
        thought: '思考过程记录',
      );
      final json = node.toJson();
      expect(json['thought'], '思考过程记录');

      final restored = ChapterNode.fromJson(json);
      expect(restored.thought, '思考过程记录');
      expect(restored.content, '正文内容');
    });

    test('copyWith 正确复制与修改 thought', () {
      final node = ChapterNode(
        chapterIndex: 1,
        title: '第一幕',
        content: '正文',
        thought: '旧思考',
      );
      final copied = node.copyWith(thought: '新思考');
      expect(copied.thought, '新思考');
      expect(copied.content, '正文');
    });
  });

  group('GameSession · 错字就地微调', () {
    test('editChapterContent 仅修改正文，快照与三位一体不变量完好', () {
      final slot = SaveSlot(
        id: 'slot_typo',
        title: '错字测试',
        worldBook: WorldBook(id: 'wb1', name: '测试'),
      );
      final session = GameSession(slot);
      session.appendChapter(
        content: '原先有错别字的正文',
        playerAction: '行动A',
        date: '1949年',
        choices: <String>['选项1', '选项2'],
        glossary: <GlossaryEntry>[],
        cast: <CastEntry>[],
        rawOutput: 'raw',
        stateRaw: '时间：1949年\n地点：北平',
        thought: '思考记录',
      );

      final stateBefore = session.worldState.copy();
      final chronicleBefore = session.chronicle;
      final nodeBefore = session.history.first;

      session.editChapterContent(0, '修正错别字之后的完美正文');

      final nodeAfter = session.history.first;
      expect(nodeAfter.content, '修正错别字之后的完美正文');
      expect(nodeAfter.playerAction, nodeBefore.playerAction);
      expect(nodeAfter.date, nodeBefore.date);
      expect(nodeAfter.thought, '思考记录');
      expect(nodeAfter.worldStateAfter?.location, '北平');
      expect(nodeAfter.chronicleAfter, chronicleBefore);
      expect(session.worldState.location, stateBefore.location);
    });
  });

  group('StoryExportService · 推演故事排版导出', () {
    final book = WorldBook(
      id: 'b1',
      name: '谍战风云',
      era: '1949年秋',
      playerRole: '潜伏特工',
    );
    final line = WorldLine(id: 'l1', name: '主线');
    final history = <ChapterNode>[
      ChapterNode(
        chapterIndex: 1,
        title: '第一幕',
        date: '1949年10月1日',
        content: '清晨的薄雾笼罩着街道。\n他推开窗户，看着远方的旗帜。',
      ),
      ChapterNode(
        chapterIndex: 2,
        title: '第二幕',
        date: '1949年10月2日',
        playerAction: '秘密联络联络员',
        content: '茶馆里人声鼎沸，切口顺利对上。',
      ),
    ];
    final worldState = WorldState(
      time: '1949年10月2日',
      location: '北平前门',
      facts: <String>['已取得信任'],
    );

    test('toMarkdown 导出结构完整包含题头、幕次、抉择与状态', () {
      final md = StoryExportService.toMarkdown(
        book: book,
        line: line,
        history: history,
        chronicle: '1949年10月：北平解放。',
        worldState: worldState,
      );

      expect(md, contains('# 谍战风云'));
      expect(md, contains('> 时代背景：1949年秋'));
      expect(md, contains('> 扮演角色：潜伏特工'));
      expect(md, contains('## 第一幕 · 1949年10月1日'));
      expect(md, contains('> **【你的抉择】** 秘密联络联络员'));
      expect(md, contains('茶馆里人声鼎沸'));
      expect(md, contains('## 编年史大事记'));
      expect(md, contains('北平解放'));
      expect(md, contains('## 当前世界观察局势'));
      expect(md, contains('北平前门'));
    });

    test('toPlainText 纯文本小说排版带全角缩进与分段', () {
      final txt = StoryExportService.toPlainText(
        book: book,
        line: line,
        history: history,
        chronicle: '1949年10月：北平解放。',
        worldState: worldState,
      );

      expect(txt, contains('《谍战风云》'));
      expect(txt, contains('第一幕 · 1949年10月1日'));
      expect(txt, contains('　　清晨的薄雾笼罩着街道。'));
      expect(txt, contains('【你的抉择】秘密联络联络员'));
      expect(txt, contains('【编年史大事记】'));
      expect(txt, contains('【当前世界观察局势】'));
    });
  });

  group('AppConfig & WakelockService · 阅读常亮', () {
    test('keepScreenOn 默认开启并支持 JSON 序列化', () {
      final cfg = AppConfig();
      expect(cfg.keepScreenOn, isTrue);

      final json = cfg.toJson();
      expect(json['keepScreenOn'], isTrue);

      final restored = AppConfig.fromJson(json);
      expect(restored.keepScreenOn, isTrue);

      final updated = cfg.copyWith(keepScreenOn: false);
      expect(updated.keepScreenOn, isFalse);
    });

    test('WakelockService 调用安全不崩溃', () async {
      await WakelockService.enable();
      await WakelockService.disable();
    });
  });
}

