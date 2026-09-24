import 'package:flutter_test/flutter_test.dart';
import 'package:nijing/models/annotation.dart';
import 'package:nijing/models/world_book.dart';
import 'package:nijing/services/response_parser.dart';

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
}
