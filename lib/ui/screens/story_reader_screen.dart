import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/game_config.dart';
import '../../models/chapter_node.dart';
import '../../scenarios/deng_1949_scenario.dart';
import '../../services/llm_service.dart';
import '../../services/storage_service.dart';
import '../themes/app_theme.dart';
import '../widgets/choice_pill_button.dart';
import '../widgets/custom_action_bar.dart';
import 'settings_drawer.dart';

/// 沉浸式小说阅读主视口 (零 HUD，全屏文学排版与流式推进)
class StoryReaderScreen extends StatefulWidget {
  final GameConfig initialConfig;
  final Function(GameConfig newConfig) onThemeConfigChanged;

  const StoryReaderScreen({
    super.key,
    required this.initialConfig,
    required this.onThemeConfigChanged,
  });

  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final LlmService _llmService = LlmService();

  late GameConfig _config;
  List<ChapterNode> _history = [];
  List<String> _currentChoices = [];

  bool _isGenerating = false;
  String _liveStreamingText = '';
  String _currentActingText = '';

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _initializeStory();
  }

  Future<void> _initializeStory() async {
    final savedHistory = await StorageService.loadHistory();
    if (savedHistory.isNotEmpty) {
      setState(() {
        _history = savedHistory;
        _currentChoices = savedHistory.last.choices;
      });
    } else {
      _startFreshStory();
    }
  }

  void _startFreshStory() {
    final prologue = Deng1949Scenario.getPrologue();
    setState(() {
      _history = [prologue];
      _currentChoices = prologue.choices;
      _liveStreamingText = '';
      _isGenerating = false;
    });
    StorageService.saveHistory(_history);
  }

  /// 玩家做出历史抉择或自由输入行动
  Future<void> _handleDecision(String action) async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _currentActingText = action;
      _liveStreamingText = '';
      _currentChoices = [];
    });

    _scrollToBottom();

    List<String> nextChoices = [];

    try {
      final stream = _llmService.streamNextChapter(
        config: _config,
        history: _history,
        playerAction: action,
        onChoicesExtracted: (choices) {
          nextChoices = choices;
        },
      );

      await for (final chunk in stream) {
        setState(() {
          _liveStreamingText += chunk;
        });
        _scrollToBottom();
      }

      // 生成完成，封存为新章节节点
      final cleanText = _liveStreamingText.replaceAll(RegExp(r'<choices>[\s\S]*$'), '').trim();
      final newChapter = ChapterNode(
        chapterIndex: _history.length + 1,
        title: "第 ${_history.length + 1} 幕：历史局势推演",
        playerAction: action,
        content: cleanText,
        choices: nextChoices,
      );

      setState(() {
        _history.add(newChapter);
        _currentChoices = nextChoices;
        _liveStreamingText = '';
        _currentActingText = '';
        _isGenerating = false;
      });

      await StorageService.saveHistory(_history);
      _scrollToBottom();

    } catch (e) {
      setState(() {
        _isGenerating = false;
        _liveStreamingText = '';
        _currentChoices = [
          "重新整理前线思路，继续推演局势",
          "严密关注敌军动向，伺机而动",
        ];
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _generateFullStoryText() {
    final buffer = StringBuffer();
    buffer.writeln("# ${Deng1949Scenario.title}");
    buffer.writeln("主角身份：${Deng1949Scenario.protagonist}");
    buffer.writeln("推演跨度：${Deng1949Scenario.timeSpan}\n");
    buffer.writeln("========================================\n");

    for (final node in _history) {
      if (node.playerAction != null && node.playerAction!.isNotEmpty) {
        buffer.writeln("【邓小平政委历史决断】：${node.playerAction}\n");
      }
      buffer.writeln("### ${node.title}\n");
      buffer.writeln("${node.content}\n");
      buffer.writeln("----------------------------------------\n");
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final fontSize = AppTheme.getFontSize(_config.fontSize);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      endDrawer: SettingsDrawer(
        config: _config,
        fullStoryText: _generateFullStoryText(),
        onConfigChanged: (newConfig) {
          setState(() => _config = newConfig);
          widget.onThemeConfigChanged(newConfig);
        },
        onRestartStory: () {
          StorageService.clearHistory();
          _startFreshStory();
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 极简沉浸顶栏：仅印鉴、标题与菜单按钮
            _buildMinimalHeader(theme, primaryColor),

            // 主小说阅读流
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // 剧本卷首扉页
                  _buildFrontispiece(theme, primaryColor),

                  // 已完成的历史章节卡片
                  for (final chapter in _history)
                    _buildChapterItem(chapter, theme, primaryColor, fontSize),

                  // 当前正在流式生成中的动态章节
                  if (_isGenerating)
                    _buildLiveGeneratingItem(theme, primaryColor, fontSize),

                  const SizedBox(height: 20),

                  // 决策操作区
                  if (!_isGenerating) ...[
                    // 动态选项胶囊列表
                    for (int i = 0; i < _currentChoices.length; i++)
                      ChoicePillButton(
                        index: i + 1,
                        text: _currentChoices[i],
                        isEnabled: !_isGenerating,
                        onTap: () => _handleDecision(_currentChoices[i]),
                      ),
                    
                    const SizedBox(height: 12),

                    // 自由意志输入栏
                    CustomActionBar(
                      isEnabled: !_isGenerating,
                      onSend: (customAction) => _handleDecision(customAction),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalHeader(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  "大历史沙盘",
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "决胜西南1949",
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.more_horiz_rounded, color: theme.colorScheme.onSurface),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrontispiece(ThemeData theme, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 28),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.8), style: BorderStyle.solid),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: primaryColor, width: 1.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              "历史演化沙盘",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            Deng1949Scenario.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.35,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Deng1949Scenario.subtitle,
            style: TextStyle(
              fontSize: 12.5,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 14),
          Container(width: 36, height: 2, color: primaryColor),
          const SizedBox(height: 12),
          Text(
            "代入身份：${Deng1949Scenario.protagonist}",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterItem(ChapterNode chapter, ThemeData theme, Color primaryColor, double fontSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapter.playerAction != null && chapter.playerAction!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
              border: Border(left: BorderSide(color: primaryColor, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "【邓小平政委决断】 ",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Expanded(
                  child: Text(
                    chapter.playerAction!,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        
        // 章节小标题
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: Text(
            chapter.title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: primaryColor,
            ),
          ),
        ),

        // 正文段落
        ...chapter.content.split('\n\n').where((p) => p.trim().isNotEmpty).map(
          (para) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              para.trim(),
              textAlign: TextAlign.justify,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.9,
                letterSpacing: 0.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),

        const Divider(height: 28),
      ],
    );
  }

  Widget _buildLiveGeneratingItem(ThemeData theme, Color primaryColor, double fontSize) {
    final cleanStreaming = _liveStreamingText.replaceAll(RegExp(r'<choices>[\s\S]*$'), '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentActingText.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
              border: Border(left: BorderSide(color: primaryColor, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "【邓小平政委决断】 ",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Expanded(
                  child: Text(
                    _currentActingText,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 呼吸生成提示
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "大西南历史齿轮推演中...",
                style: TextStyle(
                  fontSize: 12,
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // 正在流式打字的正文
        Text(
          cleanStreaming,
          textAlign: TextAlign.justify,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.9,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
