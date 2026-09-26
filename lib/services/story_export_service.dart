import '../models/chapter_node.dart';
import '../models/world_book.dart';
import '../models/world_line.dart';
import '../models/world_state.dart';
import 'text_layout.dart';

/// 推演故事排版导出服务。
///
/// 将当前推演长文按章节小说规范排版导出为带幕次、日期、抉择、编年史与世界局势的
/// 完整 Markdown 与纯文本（TXT）小说。
class StoryExportService {
  StoryExportService._();

  /// 导出为结构化 Markdown
  static String toMarkdown({
    required WorldBook book,
    required WorldLine line,
    required List<ChapterNode> history,
    String chronicle = '',
    WorldState? worldState,
  }) {
    final sb = StringBuffer();

    // 头部信息
    sb.writeln('# ${book.name.trim().isEmpty ? "未命名世界" : book.name.trim()}');
    sb.writeln();

    final meta = <String>[];
    if (book.era.trim().isNotEmpty) meta.add('时代背景：${book.era.trim()}');
    if (book.playerRole.trim().isNotEmpty) meta.add('扮演角色：${book.playerRole.trim()}');
    meta.add('推演进度：${line.name}（共 ${history.length} 幕）');
    for (final m in meta) {
      sb.writeln('> $m');
    }
    sb.writeln();
    sb.writeln('---');
    sb.writeln();

    // 正文各幕
    for (var i = 0; i < history.length; i++) {
      final node = history[i];
      final titleParts = <String>[
        node.title.trim().isEmpty ? '第 ${node.chapterIndex} 幕' : node.title.trim(),
      ];
      if (node.date.trim().isNotEmpty) {
        titleParts.add(node.date.trim());
      }

      sb.writeln('## ${titleParts.join(' · ')}');
      sb.writeln();

      final act = node.playerAction;
      if (act != null && act.trim().isNotEmpty) {
        sb.writeln('> **【你的抉择】** ${act.trim()}');
        sb.writeln();
      }

      for (final para in TextLayout.paragraphs(node.content)) {
        sb.writeln(para);
        sb.writeln();
      }

      if (i < history.length - 1) {
        sb.writeln('---');
        sb.writeln();
      }
    }

    // 编年史
    if (chronicle.trim().isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## 编年史大事记');
      sb.writeln();
      for (final line in chronicle.trim().split('\n')) {
        if (line.trim().isEmpty) continue;
        sb.writeln(line.trim());
      }
      sb.writeln();
    }

    // 当前世界局势
    if (worldState != null && worldState.isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## 当前世界观察局势');
      sb.writeln();
      if (worldState.location.isNotEmpty) {
        sb.writeln('- **当前位置**：${worldState.location}');
      }
      if (worldState.time.isNotEmpty) {
        sb.writeln('- **当前时间**：${worldState.time}');
      }
      if (worldState.relations.isNotEmpty) {
        sb.writeln('- **重要人物**：');
        for (final entry in worldState.relations.entries) {
          sb.writeln('  - ${entry.key} · ${entry.value}');
        }
      }
      if (worldState.events.isNotEmpty) {
        sb.writeln('- **正在发生**：');
        for (final ev in worldState.events) {
          sb.writeln('  - $ev');
        }
      }
      if (worldState.facts.isNotEmpty) {
        sb.writeln('- **已知事实**：');
        for (final f in worldState.facts) {
          sb.writeln('  - $f');
        }
      }
      sb.writeln();
    }

    return sb.toString().trim();
  }

  /// 导出为小说级纯文本（TXT）
  static String toPlainText({
    required WorldBook book,
    required WorldLine line,
    required List<ChapterNode> history,
    String chronicle = '',
    WorldState? worldState,
  }) {
    final sb = StringBuffer();

    // 题头
    sb.writeln('《${book.name.trim().isEmpty ? "未命名世界" : book.name.trim()}》');
    if (book.era.trim().isNotEmpty) sb.writeln('时代背景：${book.era.trim()}');
    if (book.playerRole.trim().isNotEmpty) sb.writeln('扮演角色：${book.playerRole.trim()}');
    sb.writeln('推演世界线：${line.name}（共 ${history.length} 幕）');
    sb.writeln('=' * 36);
    sb.writeln();

    for (var i = 0; i < history.length; i++) {
      final node = history[i];
      final titleParts = <String>[
        node.title.trim().isEmpty ? '第 ${node.chapterIndex} 幕' : node.title.trim(),
      ];
      if (node.date.trim().isNotEmpty) {
        titleParts.add(node.date.trim());
      }

      sb.writeln(titleParts.join(' · '));
      final act = node.playerAction;
      if (act != null && act.trim().isNotEmpty) {
        sb.writeln('【你的抉择】${act.trim()}');
      }
      sb.writeln();

      for (final para in TextLayout.paragraphs(node.content)) {
        sb.writeln('　　$para');
        sb.writeln();
      }

      if (i < history.length - 1) {
        sb.writeln('-' * 28);
        sb.writeln();
      }
    }

    if (chronicle.trim().isNotEmpty) {
      sb.writeln('=' * 36);
      sb.writeln('【编年史大事记】');
      sb.writeln(chronicle.trim());
      sb.writeln();
    }

    if (worldState != null && worldState.isNotEmpty) {
      sb.writeln('=' * 36);
      sb.writeln('【当前世界观察局势】');
      if (worldState.location.isNotEmpty) sb.writeln('当前位置：${worldState.location}');
      if (worldState.time.isNotEmpty) sb.writeln('当前时间：${worldState.time}');
      if (worldState.relations.isNotEmpty) {
        sb.writeln('重要人物：');
        for (final entry in worldState.relations.entries) {
          sb.writeln('  · ${entry.key}（${entry.value}）');
        }
      }
      if (worldState.events.isNotEmpty) {
        sb.writeln('正在发生：${worldState.events.join('；')}');
      }
      if (worldState.facts.isNotEmpty) {
        sb.writeln('已知事实：${worldState.facts.join('；')}');
      }
      sb.writeln();
    }

    return sb.toString().trim();
  }
}
