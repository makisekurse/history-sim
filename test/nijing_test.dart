import 'package:flutter_test/flutter_test.dart';
import 'package:nijing/models/annotation.dart';
import 'package:nijing/models/chapter_node.dart';
import 'package:nijing/models/save_slot.dart';
import 'package:nijing/models/world_book.dart';
import 'package:nijing/models/world_state.dart';
import 'package:nijing/services/game_session.dart';
import 'package:nijing/services/response_parser.dart';
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

  group('GameSession · 回滚与 reroll 一致性', () {
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

    test('appendChapter 写入状态快照', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天\n地点：甲地');
      expect(s.chapterCount, 1);
      expect(s.worldState.time, '第一天');
      expect(s.history.last.worldStateAfter?.time, '第一天');
      expect(s.history.last.worldStateAfter?.location, '甲地');
    });

    test('回滚到上一幕后，三者落在同一时间点', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天\n地点：甲地');
      addChapter(s, '二', '时间：第二天\n地点：乙地');
      s.attachChronicle('编年史-二');

      s.rollbackTo(0);
      expect(s.chapterCount, 1);
      expect(s.worldState.time, '第一天');
      expect(s.worldState.location, '甲地');
      expect(s.choices.first, '选项A-一');
      // 编年史也必须回到第一幕快照，而不是留在「未来」的版本
      expect(s.chronicle, '');
    });

    test('回滚到中间幕', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      addChapter(s, '二', '时间：第二天');
      addChapter(s, '三', '时间：第三天');
      s.rollbackTo(1);
      expect(s.chapterCount, 2);
      expect(s.worldState.time, '第二天');
    });

    test('reroll 不继承上一次留下的状态（关键回归）', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      addChapter(s, '二', '时间：第二天\n关系：张某|已死');
      expect(s.worldState.relations['张某'], '已死');

      s.popLastForReroll();
      // 必须回到第一幕结束时，不能还留着「张某已死」
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

    test('旧存档没有快照字段时回滚不炸', () {
      final slot = newSlot();
      slot.history = <ChapterNode>[
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
      final s = GameSession(slot);
      s.rollbackTo(0);
      expect(s.chapterCount, 1);
      expect(s.worldState.isEmpty, isTrue);
    });

    test('备份判断：起点不同才值得备份', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      expect(s.shouldBackupOver(null), isTrue);
      expect(s.shouldBackupOver(1), isFalse); // 同一幕数，不重复覆盖
      expect(s.shouldBackupOver(2), isTrue);
    });

    test('buildBackup 是深拷贝', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      final b = s.buildBackup(backupId: 'bk');
      addChapter(s, '二', '时间：第二天');
      expect(b.history.length, 1);
    });

    test('seedOpening 直接落第一幕', () {
      final s = GameSession(newSlot());
      s.seedOpening(
        content: '开场',
        date: '第一天',
        choices: <String>['x', 'y'],
      );
      expect(s.chapterCount, 1);
      expect(s.choices, <String>['x', 'y']);
      expect(s.history.first.worldStateAfter, isNotNull);
    });

    test('toSlot 把状态写回存档', () {
      final s = GameSession(newSlot());
      addChapter(s, '一', '时间：第一天');
      final slot = s.toSlot();
      expect(slot.history.length, 1);
      expect(slot.worldState.time, '第一天');
    });
  });
}
