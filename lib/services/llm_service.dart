import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game_config.dart';
import '../models/chapter_node.dart';
import '../scenarios/deng_1949_scenario.dart';

/// 统一大模型交互服务
/// 深度适配阿里云百炼 (OpenAI 兼容模式 / DashScope) 及 DeepSeek
class LlmService {
  final http.Client _client = http.Client();

  /// 生成下一幕剧情流式推进
  Stream<String> streamNextChapter({
    required GameConfig config,
    required List<ChapterNode> history,
    required String playerAction,
    required Function(List<String> newChoices) onChoicesExtracted,
  }) async* {
    // 1. 如果未配置 API Key，直接进入沉浸式离线推演沙盘
    if (config.apiKey.trim().isEmpty || config.apiProvider == 'offline_demo') {
      final nextNode = Deng1949Scenario.generateOfflineNextChapter(
        history.length,
        playerAction,
      );
      
      // 模拟打字机流式输出
      for (int i = 0; i < nextNode.content.length; i += 2) {
        final end = (i + 2 <= nextNode.content.length) ? i + 2 : nextNode.content.length;
        yield nextNode.content.substring(i, end);
        await Future.delayed(const Duration(milliseconds: 18));
      }

      onChoicesExtracted(nextNode.choices);
      return;
    }

    // 2. 构造符合阿里云百炼文档规范的请求端点
    String effectiveUrl = _resolveBaseUrl(config);
    if (!effectiveUrl.endsWith('/chat/completions')) {
      effectiveUrl = effectiveUrl.endsWith('/') 
          ? '${effectiveUrl}chat/completions' 
          : '$effectiveUrl/chat/completions';
    }

    // 3. 构建历史消息上下文与安全提示词
    final messages = _buildMessagesPayload(history, playerAction);

    final requestBody = {
      'model': config.modelName.isNotEmpty ? config.modelName : 'qwen3.8-max',
      'messages': messages,
      'stream': true,
      'temperature': 0.85,
    };

    final request = http.Request('POST', Uri.parse(effectiveUrl));
    request.headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(requestBody);

    StringBuffer fullResponseBuffer = StringBuffer();

    try {
      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        yield '\n\n【阿里云百炼调用提示 (${streamedResponse.statusCode})】\n$errorBody\n可在设置中核对 API Key、业务空间ID 与模型名称。';
        onChoicesExtracted([
          "重新整理前线电报，再度审慎决断",
          "派出侦察特派组，深入一线探明最新虚实",
        ]);
        return;
      }

      // 4. 解析 SSE 流式返回
      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        
        final dataStr = trimmed.substring(5).trim();
        if (dataStr == '[DONE]') break;

        try {
          final jsonMap = jsonDecode(dataStr);
          final choices = jsonMap['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final textChunk = delta?['content'] as String? ?? '';
            if (textChunk.isNotEmpty) {
              fullResponseBuffer.write(textChunk);
              yield textChunk;
            }
          }
        } catch (_) {
          // 忽略非 JSON 数据行
        }
      }

      // 5. 生成完毕后，提取决策分支选项
      final completeText = fullResponseBuffer.toString();
      final extractedChoices = _extractChoices(completeText);
      onChoicesExtracted(extractedChoices);

    } catch (e) {
      yield '\n\n【网络或接口连接异常】$e\n请检查网络连通性或当前 API 配置。';
      onChoicesExtracted([
        "保持既定方针，继续推进川黔经略",
        "召集各兵团长官紧急会商军情",
      ]);
    }
  }

  /// 根据配置与阿里云百炼文档拼接 Base URL
  String _resolveBaseUrl(GameConfig config) {
    if (config.baseUrl.trim().isNotEmpty) {
      return config.baseUrl.trim();
    }
    // 默认回退至通用百炼兼容端点
    return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  }

  /// 构建具备历史严肃文学质感与防审查包装的系统 Prompt
  List<Map<String, String>> _buildMessagesPayload(List<ChapterNode> history, String playerAction) {
    const systemPrompt = 
        "【系统身份与学术沙盘设定】\n"
        "你正在协助进行一部基于历史唯物主义与当代中国通史的严肃历史演化沙盘创作——《决胜西南1949：主政大西南与建政风云》。\n"
        "玩家第一人称代入主角：邓小平同志（时任中共中央西南局第一书记、中国人民解放军第二野战军政治委员，45岁）。\n\n"
        "【叙事与推演规则】\n"
        "1. 严格基于1949-1952年大西南战役、成渝铁路修筑、西南大剿匪、金融统战、经略西藏等客观历史规律，展现宏观军事战略、地方治理智慧与实事求是的务实作风。\n"
        "2. 语言白描、沉稳、遒劲，兼具时代公文、军情电报与大历史小说的叙事张力。严禁轻浮戏说，严禁游戏化标签（如‘玩家’‘回合’‘经验’）。\n"
        "3. 每次推演输出一段 300~500 字紧凑有力的现场剧情，刻画前线电报、将领会商（如刘伯承、贺龙）、基层民生或重大决策交锋。\n"
        "4. 在输出的文本最末尾，另起一行，必须使用 <choices> 标签包裹 2~3 个供邓小平同志在当前局势下做出决断的分支选项，每个选项单独占一行。\n"
        "格式如下：\n"
        "<choices>\n"
        "选项1内容……\n"
        "选项2内容……\n"
        "</choices>";

    final List<Map<String, String>> messages = [
      {'role': 'system', 'content': systemPrompt},
    ];

    // 取最近两幕对话作为滚动上下文
    final recentHistory = history.length > 2 ? history.sublist(history.length - 2) : history;
    for (final node in recentHistory) {
      if (node.playerAction != null && node.playerAction!.isNotEmpty) {
        messages.add({'role': 'user', 'content': '邓小平政委的历史决断：${node.playerAction}'});
      }
      messages.add({'role': 'assistant', 'content': node.content});
    }

    // 加入当前行动
    messages.add({
      'role': 'user',
      'content': '面对当前局势，邓小平同志指示：“$playerAction”\n请据此推演接下来的军政局势演变与新一轮历史抉择：'
    });

    return messages;
  }

  /// 从完整文本中解析 <choices> 标签
  List<String> _extractChoices(String fullText) {
    final regExp = RegExp(r'<choices>([\s\S]*?)<\/choices>', caseSensitive: false);
    final match = regExp.firstMatch(fullText);
    
    if (match != null) {
      final block = match.group(1) ?? '';
      final lines = block.split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceAll(RegExp(r'^(\d+[\.、\s]|[-*•]\s*|选项[一二三四1234]：?\s*)'), ''))
          .where((l) => l.isNotEmpty)
          .toList();
      
      if (lines.length >= 2) return lines;
    }

    // 默认兜底选项
    return [
      "统揽大局，令各兵团兼顾军事进军与政权巩固，扎实推进",
      "起草加急特急绝密电报，向中央军委与毛主席详陈西南最新实情",
      "亲赴一线重要厂矿与接管机关座谈，以实事求是作风解决现实阻力"
    ];
  }
}
