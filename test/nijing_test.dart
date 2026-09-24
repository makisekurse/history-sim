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

  group('ResponseParser', () {
    const sample = '''
<date>1949年11月30日</date>
重庆解放了。雾气笼罩着山城。

<choices>
1. 立即调运川北粮食入渝平价倾销
2. 出动纠察队封锁黑市，取缔银元交易
</choices>

<glossary>
袁大头|民国时期流通的银元
袍哥|四川地区的帮会组织
</glossary>

<cast>
刘伯承|第二野战军司令员|坚定支持
</cast>
''';

    test('拆出正文与全部结构块', () {
      final parsed = ResponseParser.parse(sample);
      expect(parsed.date, '1949年11月30日');
      expect(parsed.choices.length, 2);
      expect(parsed.choices.first.startsWith('立即调运'), isTrue);
      expect(parsed.glossary.length, 2);
      expect(parsed.glossary.first.term, '袁大头');
      expect(parsed.cast.length, 1);
      expect(parsed.cast.first.name, '刘伯承');
      expect(parsed.body.contains('<choices>'), isFalse);
      expect(parsed.body.contains('重庆解放了'), isTrue);
      expect(parsed.hasUsableChoices, isTrue);
    });

    test('缺 choices 时判定不可用', () {
      final parsed = ResponseParser.parse('只有一段正文，没有结构块。');
      expect(parsed.hasUsableChoices, isFalse);
    });

    test('流式预览会隐藏半截标签', () {
      const streaming = '正文开始…\n\n<choices>\n第一条';
      final preview = ResponseParser.stripForPreview(streaming);
      expect(preview.contains('<choices>'), isFalse);
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
