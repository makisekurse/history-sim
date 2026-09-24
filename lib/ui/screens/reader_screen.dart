import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../data/secure_store.dart';
import '../../models/app_config.dart';
import '../../models/chapter_node.dart';
import '../../models/save_slot.dart';
import '../../services/chronicle_service.dart';
import '../../services/fallback_service.dart';
import '../../services/llm_client.dart';
import '../../services/response_parser.dart';
import '../../services/save_service.dart';
import '../themes/app_theme.dart';
import '../widgets/choice_pill.dart';
import '../widgets/free_input_bar.dart';
import '../widgets/glossary_sheet.dart';
import 'cast_screen.dart';
import 'chronicle_screen.dart';
import 'settings_screen.dart';

/// 沉浸式阅读主视口。
///
/// 零 HUD：顶栏默认隐藏，轻触屏幕中央淡入、3 秒无操作淡出。
/// 界面上**没有任何写死的剧本信息**，全部来自当前世界书。
class ReaderScreen extends StatefulWidget {
  final AppConfig config;
  final SaveSlot slot;
  final ValueChanged<AppConfig> onConfigChanged;

  const ReaderScreen({
    super.key,
    required this.config,
    required this.slot,
    required this.onConfigChanged,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _scroll = ScrollController();
  final LlmClient _client = LlmClient();

  late AppConfig _config;
  late SaveSlot _slot;

  List<ChapterNode> _history = <ChapterNode>[];
  String _chronicle = '';
  List<String> _choices = <String>[];

  bool _busy = false;
  String _pendingAction = '';
  String _live = '';
  String _typerBuffer = '';
  Timer? _typer;
  String _notice = '';
  bool _degraded = false;

  bool _headerVisible = true;
  Timer? _headerTimer;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _slot = widget.slot;
    _history = List<ChapterNode>.from(_slot.history);
    _chronicle = _slot.chronicle;
    if (_history.isNotEmpty) {
      _choices = List<String>.from(_history.last.choices);
    }
    _scroll.addListener(_onScroll);
    _scheduleHeaderHide();
    _loadApiKey();
  }

  @override
  void dispose() {
    _typer?.cancel();
    _headerTimer?.cancel();
    _client.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- 顶栏自动隐藏 ----------

  void _scheduleHeaderHide() {
    _headerTimer?.cancel();
    if (!_config.autoHideHeader) return;
    _headerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _headerVisible = false);
    });
  }

  void _toggleHeader() {
    setState(() => _headerVisible = !_headerVisible);
    if (_headerVisible) _scheduleHeaderHide();
  }

  // ---------- 滚动跟随 ----------
  //
  // 旧版每来一个 chunk 就强行滚到底，用户往回翻看前文会被反复拽走。
  // 现在只有「已经在底部附近」时才跟随。

  bool _atBottom = true;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final cur = _scroll.position.pixels;
    _atBottom = (max - cur) < 120;
  }

  void _follow() {
    if (!_atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------- 打字机 ----------

  void _feed(String chunk) {
    if (!_config.typewriter) {
      setState(() => _live += chunk);
      _follow();
      return;
    }
    _typerBuffer += chunk;
    _typer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_typerBuffer.isEmpty) {
        _typer?.cancel();
        _typer = null;
        return;
      }
      const step = 3;
      final take =
          _typerBuffer.length >= step ? step : _typerBuffer.length;
      setState(() {
        _live += _typerBuffer.substring(0, take);
        _typerBuffer = _typerBuffer.substring(take);
      });
      _follow();
    });
  }

  void _skipTyping() {
    if (_typerBuffer.isEmpty) return;
    _typer?.cancel();
    _typer = null;
    setState(() {
      _live += _typerBuffer;
      _typerBuffer = '';
    });
    _follow();
  }

  // ---------- 生成 ----------

  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pendingAction = action;
      _live = '';
      _typerBuffer = '';
      _choices = <String>[];
      _notice = '';
      _degraded = false;
    });
    _atBottom = true;
    _follow();

    ParsedChapter? parsed;
    var degraded = false;

    final stream = FallbackService(_client).generate(
      config: _config,
      apiKey: _apiKey,
      book: _slot.worldBook,
      history: _history,
      playerAction: action,
      chronicle: _chronicle,
    );

    await for (final ev in stream) {
      if (!mounted) return;
      switch (ev.kind) {
        case GenEventKind.delta:
          _feed(ev.text);
          break;
        case GenEventKind.notice:
          setState(() => _notice = ev.text);
          break;
        case GenEventKind.done:
          parsed = ev.chapter;
          degraded = ev.degraded;
          break;
        case GenEventKind.failed:
          setState(() => _notice = ev.text);
          break;
      }
    }

    _skipTyping();

    if (parsed != null) {
      final node = ChapterNode(
        chapterIndex: _history.length + 1,
        title: '第 ${_history.length + 1} 幕',
        content: parsed.body,
        playerAction: action,
        date: parsed.date,
        choices: parsed.choices,
        glossary: parsed.glossary,
        cast: parsed.cast,
      );
      setState(() {
        _history = <ChapterNode>[..._history, node];
        _choices = parsed!.choices;
        _live = '';
        _pendingAction = '';
        _busy = false;
        _degraded = degraded;
      });
      await _persist();
      await _maybeCompressChronicle();
    } else {
      setState(() {
        _busy = false;
        _live = '';
        _pendingAction = '';
      });
    }
    _follow();
  }

  String _apiKey = '';

  Future<void> _persist() async {
    _slot.history = _history;
    _slot.chronicle = _chronicle;
    await SaveService.upsert(_slot);
  }

  Future<void> _maybeCompressChronicle() async {
    if (!ChronicleService.shouldCompress(_history.length)) return;
    if (_apiKey.trim().isEmpty) return;
    final updated = await ChronicleService.compress(
      config: _config,
      apiKey: _apiKey,
      book: _slot.worldBook,
      previousChronicle: _chronicle,
      history: _history,
    );
    if (!mounted) return;
    if (updated != _chronicle) {
      setState(() => _chronicle = updated);
      await _persist();
    }
  }

  /// 重新生成当前这一幕（回退一幕再重跑同样的决定）。
  Future<void> _rerollLast() async {
    if (_busy || _history.isEmpty) return;
    final last = _history.last;
    final action = last.playerAction;
    if (action == null || action.trim().isEmpty) return;

    setState(() {
      _history = _history.sublist(0, _history.length - 1);
      _choices = _history.isEmpty ? <String>[] : _history.last.choices;
    });
    await _act(action);
  }

  /// 回滚到第 [index] 幕（index 从 0 起），之后的内容全部丢弃。
  Future<void> _rollbackTo(int index) async {
    if (_busy) return;
    final target = _history[index];
    setState(() {
      _history = _history.sublist(0, index + 1);
      _choices = List<String>.from(target.choices);
      _live = '';
      _pendingAction = '';
    });
    await _persist();
  }

  void _cancel() {
    _client.cancel();
    setState(() {
      _busy = false;
      _notice = '已中止本次推演。';
    });
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = AppTheme.getFontSize(_config.fontSize);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_busy) {
                        _skipTyping();
                      } else {
                        _toggleHeader();
                      }
                    },
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      children: <Widget>[
                        _frontispiece(theme),
                        for (var i = 0; i < _history.length; i++)
                          _chapterView(theme, _history[i], fontSize, i),
                        if (_busy) _liveView(theme, fontSize),
                        if (_notice.isNotEmpty) _noticeView(theme),
                        const SizedBox(height: 16),
                        if (!_busy) ...<Widget>[
                          if (_history.isEmpty && _choices.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => _act(''),
                                  icon: const Icon(Icons.auto_stories_rounded,
                                      size: 18),
                                  label: const Text('开始推演'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        theme.colorScheme.primary,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                            ),
                          for (var i = 0; i < _choices.length; i++)
                            ChoicePill(
                              index: i + 1,
                              text: _choices[i],
                              enabled: !_busy,
                              onTap: () => _act(_choices[i]),
                            ),
                          const SizedBox(height: 6),
                          FreeInputBar(
                            busy: false,
                            onSend: _act,
                            onCancel: _cancel,
                          ),
                        ] else
                          FreeInputBar(
                            busy: true,
                            onSend: _act,
                            onCancel: _cancel,
                          ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _header(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return AnimatedOpacity(
      opacity: _headerVisible ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: IgnorePointer(
        ignoring: !_headerVisible,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withValues(alpha: 0.94),
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.8),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _slot.worldBook.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '第 ${_history.length} 幕 · ${_slot.worldBook.era.isEmpty ? AppInfo.appName : _slot.worldBook.era}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编年史',
                icon: Icon(Icons.timeline_rounded,
                    color: theme.colorScheme.onSurface),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChronicleScreen(history: _history),
                  ),
                ),
              ),
              IconButton(
                tooltip: '更多',
                icon: Icon(Icons.more_horiz_rounded,
                    color: theme.colorScheme.onSurface),
                onPressed: _openMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.timeline_rounded),
              title: const Text('编年史时间线'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChronicleScreen(history: _history),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: const Text('人物志'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CastScreen(history: _history),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('本幕词条'),
              onTap: () {
                Navigator.pop(ctx);
                if (_history.isEmpty) return;
                AnnotationSheet.showGlossary(
                    context, _history.last.glossary);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('重新生成本幕'),
              enabled: !_busy && _history.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                _rerollLast();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('回滚到某一幕'),
              enabled: !_busy && _history.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                _showRollbackPicker();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('设置'),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      config: _config,
                      onConfigChanged: (c) {
                        setState(() => _config = c);
                        widget.onConfigChanged(c);
                      },
                    ),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRollbackPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _history.length,
            itemBuilder: (_, i) {
              final node = _history[i];
              final isLast = i == _history.length - 1;
              return ListTile(
                dense: true,
                title: Text(
                  '第 ${node.chapterIndex} 幕'
                  '${node.date.isEmpty ? '' : ' · ${node.date}'}',
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: node.playerAction == null
                    ? null
                    : Text(
                        node.playerAction!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                trailing: isLast ? const Text('当前') : null,
                enabled: !isLast,
                onTap: !isLast
                    ? () {
                        Navigator.pop(ctx);
                        _rollbackTo(i);
                      }
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _frontispiece(ThemeData theme) {
    final book = _slot.worldBook;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 26),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.primary,
                width: 1.1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              AppInfo.appName,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            book.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (book.era.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              book.era.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(width: 36, height: 2, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            '你扮演：${book.playerRole.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterView(
    ThemeData theme,
    ChapterNode chapter,
    double fontSize,
    int index,
  ) {
    final act = chapter.playerAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (act != null && act.trim().isNotEmpty) _actionCard(theme, act),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  chapter.date.trim().isEmpty
                      ? chapter.title
                      : '${chapter.title} · ${chapter.date.trim()}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              if (chapter.glossary.isNotEmpty)
                _miniAction(
                  theme,
                  Icons.info_outline_rounded,
                  () => AnnotationSheet.showGlossary(context, chapter.glossary),
                ),
              if (chapter.cast.isNotEmpty)
                _miniAction(
                  theme,
                  Icons.groups_outlined,
                  () => AnnotationSheet.showCast(context, chapter.cast),
                ),
            ],
          ),
        ),
        for (final para in chapter.content
            .split('\n\n')
            .where((p) => p.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              para.trim(),
              textAlign: _config.verticalText
                  ? TextAlign.start
                  : TextAlign.justify,
              style: TextStyle(
                fontSize: fontSize,
                height: _config.lineHeight,
                letterSpacing: _config.verticalText ? 1.6 : 0.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        const Divider(height: 26),
      ],
    );
  }

  Widget _miniAction(ThemeData theme, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          icon,
          size: 16,
          color: theme.colorScheme.primary.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _actionCard(ThemeData theme, String act) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '【决定】 ',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          Expanded(
            child: Text(
              act,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveView(ThemeData theme, double fontSize) {
    final preview = ResponseParser.stripForPreview(_live);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_pendingAction.isNotEmpty) _actionCard(theme, _pendingAction),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _degraded ? '本地降级中…' : '推演中…（轻触可跳过打字）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (preview.isNotEmpty)
          Text(
            preview,
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontSize: fontSize,
              height: _config.lineHeight,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurface,
            ),
          ),
      ],
    );
  }

  Widget _noticeView(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(
        _notice,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  bool _apiKeyLoaded = false;

  Future<void> _loadApiKey() async {
    if (_apiKeyLoaded) return;
    _apiKeyLoaded = true;
    final key = await SecureStore.readApiKey();
    if (mounted) setState(() => _apiKey = key);
  }
}
