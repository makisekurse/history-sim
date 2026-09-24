import '../models/app_config.dart';
import '../models/chapter_node.dart';
import '../models/world_book.dart';
import 'llm_client.dart';

/// 编年史滚动摘要。
///
/// 旧版每幕只带最近 2 幕上下文，玩到第 20 幕模型已经完全忘了前面发生过什么。
/// 这里每积累 [compressEvery] 幕就把「已发生的事实」压缩成一段摘要，
/// 塞进 system prompt —— 既省 token，又让长局保持连贯。
class ChronicleService {
  ChronicleService._();

  static const int compressEvery = 5;

  /// 是否到了该压缩的节点。
  static bool shouldCompress(int chapterCount) =>
      chapterCount > 0 && chapterCount % compressEvery == 0;

  static const String _instruction = '''
你是历史推演的档案整理员。下面是一段推演记录，请把它压缩成「前情编年史」。

要求：
1. 按时间顺序列出已发生的关键事实：时间、地点、人物、做出的决定、造成的结果。
2. 只保留对后续推演有约束力的事实，不要抒情、不要评论、不要预测。
3. 保持人称一致（以主角的视角记录），不要出现"玩家""回合"等词。
4. 控制在 400 字以内，用短句分行。
5. 直接输出编年史正文，不要任何前后缀说明。''';

  /// 压缩出一段新的编年史摘要。失败时返回原摘要，不影响主线。
  static Future<String> compress({
    required AppConfig config,
    required String apiKey,
    required WorldBook book,
    required String previousChronicle,
    required List<ChapterNode> history,
    String workspaceId = '',
  }) async {
    if (history.isEmpty) return previousChronicle;

    final client = LlmClient();
    try {
      final transcript = StringBuffer();
      if (previousChronicle.trim().isNotEmpty) {
        transcript.writeln('【已有编年史】');
        transcript.writeln(previousChronicle.trim());
        transcript.writeln();
      }
      transcript.writeln('【新增记录】');
      for (final node in history) {
        if (node.date.trim().isNotEmpty) {
          transcript.writeln('时间：${node.date.trim()}');
        }
        final act = node.playerAction;
        if (act != null && act.trim().isNotEmpty) {
          transcript.writeln('决定：${act.trim()}');
        }
        final body = node.content.trim();
        if (body.isNotEmpty) {
          transcript.writeln(
            '结果：${body.length > 600 ? '${body.substring(0, 600)}…' : body}',
          );
        }
        transcript.writeln('---');
      }

      final messages = <Map<String, String>>[
        <String, String>{'role': 'system', 'content': _instruction},
        <String, String>{
          'role': 'user',
          'content': '世界书名：${book.name}\n\n${transcript.toString()}',
        },
      ];

      final buffer = StringBuffer();
      await for (final delta in client.streamChat(
        config: config,
        apiKey: apiKey,
        messages: messages,
        workspaceId: workspaceId,
      )) {
        buffer.write(delta);
      }
      final out = buffer.toString().trim();
      if (out.isEmpty) return previousChronicle;
      return out;
    } catch (_) {
      // 摘要失败不能影响推演主线。
      return previousChronicle;
    } finally {
      client.cancel();
    }
  }
}
