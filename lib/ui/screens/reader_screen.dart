import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../data/secure_store.dart';
import '../../models/app_config.dart';
import '../../models/chapter_node.dart';
import '../../models/save_slot.dart';
import '../../models/world_state.dart';
import '../../services/chronicle_service.dart';
import '../../services/fallback_service.dart';
import '../../services/game_session.dart';
import '../../services/llm_client.dart';
import '../../services/response_parser.dart';
import '../../services/save_service.dart';
import '../../services/text_layout.dart';
import '../../services/world_state_service.dart';
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

  /// 状态与纯逻辑都在这里（可单测）；本类只负责展示与交互。
  late GameSession _session;

  // 读操作走 getter 委托，尽量少改动既有代码。
  List<ChapterNode> get _history => _session.history;
  String get _chronicle => _session.chronicle;
  WorldState get _worldState => _session.worldState;
  List<String> get _choices => _session.choices;

  bool _busy = false;
  String _pendingAction = '';
  String _live = '';
  String _notice = '';
  bool _degraded = false;

  bool _headerVisible = true;
  Timer? _headerTimer;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _slot = widget.slot;
    _session = GameSession(_slot);
    _scroll.addListener(_onScroll);
    _enterImmersive();
    _scheduleHeaderHide();
    _loadApiKey();
    _maybeJumpToLatest();
  }

  @override
  void dispose() {
    _headerTimer?.cancel();
    _client.cancel();
    _scroll.dispose();
    _exitImmersive();
    super.dispose();
  }

  // ---------- 沉浸模式 ----------
  //
  // 阅读时把系统状态栏与导航栏藏起来，让屏幕只剩文字。
  //
  // 用 immersiveSticky 而不是 immersive：从屏幕边缘上滑能临时唤出系统栏，
  // 几秒后自动缩回 —— 用户随时能看到时间和电量，不会觉得「被困住」。

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---------- 顶栏自动隐藏 ----------

  void _scheduleHeaderHide() {
    _headerTimer?.cancel();
    if (!_config.autoHideHeader) return;
    _headerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _headerVisible = false);
    });
  }

  /// 单击唤出顶栏 —— **只显示，不切换**。
  ///
  /// 之前是 toggle，导致「想唤出结果反而关掉了」，体感很怪。
  /// 现在单击一律显示并重置自动隐藏计时；隐藏交给 3 秒定时器。
  void _showHeader() {
    if (!_headerVisible) {
      setState(() => _headerVisible = true);
    }
    _scheduleHeaderHide();
  }

  /// 最新一幕的锚点。跳转用它而不是 `maxScrollExtent`。
  final GlobalKey _latestKey = GlobalKey();

  /// 打开推演时跳到最新一幕。
  ///
  /// 「继续进入」的语义就是**接着上次的进度往下** —— 默认停在第一幕的话，
  /// 用户得手动翻到底，等于每次进来都要重新找位置。
  ///
  /// ⚠️ 不用 `jumpTo(maxScrollExtent)` 一步到位：ListView 是懒加载的，
  /// 首帧之后 `maxScrollExtent` 只反映**已经铺出来**的那部分，直接跳会落在半路。
  /// 所以先 `ensureVisible` 定位到最后一幕，下一帧再补一次到底。
  void _maybeJumpToLatest() {
    if (!_config.autoScrollToLatest) return;
    if (_history.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _latestKey.currentContext;
      if (ctx != null) {
        _atBottom = true;
        Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 1);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _atBottom = true;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });
  }

  // ---------- 原始指针：区分「单击」与「划选」 ----------
  //
  // 2026-09-25 二次修。上一版把 GestureDetector 换成 Listener 之后**仍然唤不出**，
  // 原因是又加了两个额外守卫：「当前有选中文字」与「落点在底部操作区」。
  // 只要其中任何一个判断卡住（比如选过一次文字后 onSelectionChanged 没回调
  // null），顶栏就彻底唤不出来了。
  //
  // 现在**只保留一个判断：指针有没有拖动**。
  // 拖动 = 滚动或划选，其余一律当作单击。
  // 宁可偶尔多弹一次，也不能让用户唤不出顶栏。

  Offset? _pointerDown;
  bool _pointerMoved = false;

  void _onPointerDown(PointerDownEvent e) {
    _pointerDown = e.position;
    _pointerMoved = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final d = _pointerDown;
    if (d == null || _pointerMoved) return;
    if ((e.position - d).distance > 12) _pointerMoved = true;
  }

  void _onPointerUp(PointerUpEvent e) {
    final wasDrag = _pointerMoved;
    _pointerDown = null;
    _pointerMoved = false;
    if (wasDrag) return;
    _showHeader();
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

  // ---------- 流式文本 ----------
  //
  // 2026-09-25 移除了打字机效果：它只是把已经到手的文字延迟显示，
  // 除了让人等之外没有实际价值，还额外引入一个 16ms 定时器与「跳过」状态。
  // 现在模型吐多少就显示多少。

  void _feed(String chunk) {
    setState(() => _live += chunk);
    _follow();
  }

  // ---------- 生成 ----------

  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pendingAction = action;
      _live = '';
      _session.clearChoices();
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
      worldState: WorldStateService.renderForPrompt(_worldState),
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

    final p = parsed;
    if (p != null) {
      setState(() {
        // 合并世界状态、写入本幕快照，全在 GameSession 里完成
        _session.appendChapter(
          content: p.body,
          playerAction: action,
          date: p.date,
          choices: p.choices,
          glossary: p.glossary,
          cast: p.cast,
          rawOutput: p.rawOutput,
          stateRaw: p.stateRaw,
        );
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
    await SaveService.upsert(_session.toSlot());
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
      // 把新摘要记到最后一幕的快照上，这样以后回滚到这一幕时
      // 能恢复到正确的编年史，而不是「未来」的版本。
      setState(() => _session.attachChronicle(updated));
      await _persist();
    }
  }

  /// 重新生成当前这一幕。
  ///
  /// ⚠️ 必须先把 chronicle / worldState 恢复到**这一幕之前**的样子再重跑，
  /// 否则第二次生成会继承第一次留下的状态（例如「张某已死」还在），
  /// 整个状态就脏了。
  Future<void> _rerollLast() async {
    if (_busy || _history.isEmpty) return;
    final last = _history.last;
    final action = last.playerAction;
    if (action == null || action.trim().isEmpty) return;

    setState(() {
      // 弹出最后一幕，并把 chronicle / worldState 恢复到这一幕**之前**
      _session.popLastForReroll();
      _live = '';
      _pendingAction = '';
      _notice = '';
    });
    await _act(action);
  }

  /// 回滚到第 [index] 幕（index 从 0 起），之后的内容全部丢弃。
  ///
  /// ⚠️ history / chronicle / worldState **三者必须回到同一个时间点**，
  /// 否则模型会「记得」那些已经被撤销的未来。
  Future<void> _rollbackTo(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _history.length) return;
    final chapterNo = _history[index].chapterIndex;

    // 回滚会永久丢弃后面的幕，先自动备份当前分支
    await _backupBeforeRollback();
    if (!mounted) return;

    setState(() {
      // history / chronicle / worldState 三者一起回到同一时间点
      _session.rollbackTo(index);
      _live = '';
      _pendingAction = '';
      _notice = '已回滚到第 $chapterNo 幕，其后的内容已丢弃。';
    });
    await _persist();
  }

  /// 回滚前自动备份当前分支。
  ///
  /// **单槽覆盖**：每个存档只保留一个备份槽，连续回滚不会堆出一堆重复存档。
  /// 起点与上次相同（幕数一样）时不重复覆盖，避免把更早的分支冲掉。
  Future<void> _backupBeforeRollback() async {
    final backupId = SaveSlot.backupIdFor(_slot.id);
    final existing = await SaveService.findById(backupId);
    if (!_session.shouldBackupOver(existing?.history.length)) return;
    await SaveService.upsert(
      _session.buildBackup(backupId: backupId, createdAt: existing?.createdAt),
    );
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
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      children: <Widget>[
                        // 阅读区整体可长按选中复制。
                        // ⚠️ 选择胶囊与输入框必须留在 SelectionArea **外面**，
                        // 否则选中手势会和按钮点击打架。
                        SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _frontispiece(theme),
                              for (var i = 0; i < _history.length; i++)
                                _chapterView(
                                  theme,
                                  _history[i],
                                  fontSize,
                                  i,
                                  anchorKey: i == _history.length - 1
                                      ? _latestKey
                                      : null,
                                ),
                              if (_busy) _liveView(theme, fontSize),
                              if (_notice.isNotEmpty) _noticeView(theme),
                            ],
                          ),
                        ),
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
    final palette = AppTheme.readingOf(context);
    return AnimatedOpacity(
      opacity: _headerVisible ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: IgnorePointer(
        ignoring: !_headerVisible,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          decoration: BoxDecoration(
            color: palette.scrim,
            border: Border(
              bottom: BorderSide(color: palette.rule, width: 0.8),
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
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      _statusLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              // 编年史 / 人物志 / 世界观察 / 更多 —— 顶栏就是内容入口
              _headerAction(
                palette,
                icon: Icons.timeline_rounded,
                tooltip: '编年史',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChronicleScreen(history: _history),
                  ),
                ),
              ),
              _headerAction(
                palette,
                icon: Icons.groups_outlined,
                tooltip: '人物志',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CastScreen(history: _history),
                  ),
                ),
              ),
              _headerAction(
                palette,
                icon: Icons.explore_outlined,
                tooltip: '世界观察',
                onTap: _showWorldState,
              ),
              _headerAction(
                palette,
                icon: Icons.more_horiz_rounded,
                tooltip: '更多',
                onTap: _openMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerAction(
    ReadingPalette palette, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      IconButton(
        tooltip: tooltip,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: palette.ink),
        onPressed: onTap,
      );

  /// 顶栏第二行：极轻量，一行放下「第 N 幕 · 地点 · 时间」。
  String _statusLine() {
    final parts = <String>['第 ${_history.length} 幕'];
    final summary = _worldState.inlineSummary;
    if (summary.isNotEmpty) {
      parts.add(summary);
    } else if (_slot.worldBook.era.trim().isNotEmpty) {
      parts.add(_slot.worldBook.era.trim());
    }
    return parts.join(' · ');
  }

  /// 世界观察：默认收起，只在用户主动点开时才展开。
  /// 普通玩家只看小说，想看局势的人才用得到。
  void _showWorldState() {
    final theme = Theme.of(context);
    final s = _worldState;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '世界观察',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: s.isEmpty
                        ? Text(
                            '还没有世界状态。\n推演一幕之后，这里会记录此刻的时间、'
                            '地点、人物关系与未决之事。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.8,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _stateSection(theme, '当前位置',
                                  s.location.isEmpty ? '—' : s.location),
                              _stateSection(theme, '当前时间',
                                  s.time.isEmpty ? '—' : s.time),
                              if (s.relations.isNotEmpty)
                                _stateSection(
                                  theme,
                                  '重要人物',
                                  s.relations.entries
                                      .map((e) => '${e.key} · ${e.value}')
                                      .join('\n'),
                                ),
                              if (s.events.isNotEmpty)
                                _stateSection(
                                    theme, '正在发生', s.events.join('\n')),
                              if (s.facts.isNotEmpty)
                                _stateSection(
                                    theme, '你已知晓', s.facts.join('\n')),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateSection(ThemeData theme, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.7,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      );

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
              leading: const Icon(Icons.explore_outlined),
              title: const Text('世界观察'),
              subtitle: const Text('此刻的时间、地点、人物与未决之事'),
              onTap: () {
                Navigator.pop(ctx);
                _showWorldState();
              },
            ),
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
    final palette = AppTheme.readingOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 26),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.rule)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: palette.accent, width: 1.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              AppInfo.appName,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: palette.accent,
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
              color: palette.ink,
            ),
          ),
          if (book.era.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              book.era.trim(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: palette.muted),
            ),
          ],
          const SizedBox(height: 14),
          Container(width: 36, height: 2, color: palette.accent),
          const SizedBox(height: 12),
          Text(
            '你扮演：${book.playerRole.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.muted,
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
    int index, {
    Key? anchorKey,
  }) {
    final palette = AppTheme.readingOf(context);
    final act = chapter.playerAction;
    return Column(
      key: anchorKey,
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
                    color: palette.accent,
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
              _miniAction(
                theme,
                Icons.more_horiz_rounded,
                () => _chapterMenu(chapter),
              ),
            ],
          ),
        ),
        for (final para in TextLayout.paragraphs(chapter.content))
          Padding(
            padding: EdgeInsets.only(
              bottom: TextLayout.spacing(_config.paragraphSpacing),
            ),
            child: Text(
              // 段首缩进用全角空格（U+3000）—— 中文字体下才等于一个汉字宽
              '${TextLayout.indent(_config.paragraphIndent)}$para',
              textAlign: TextAlign.justify,
              style: TextStyle(
                fontSize: fontSize,
                height: _config.lineHeight,
                letterSpacing: 0.4,
                color: palette.ink,
              ),
            ),
          ),
        Divider(height: 26, color: palette.rule),
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

  /// 本幕操作菜单。复制与原始输出都收在这里，不占用正文空间，
  /// 也不破坏「像小说阅读器」的观感。
  void _chapterMenu(ChapterNode chapter) {
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
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制本幕'),
              subtitle: const Text('标题 + 你的行动 + 正文'),
              onTap: () {
                Navigator.pop(ctx);
                _copyChapter(chapter);
              },
            ),
            if (chapter.glossary.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('本幕词条'),
                onTap: () {
                  Navigator.pop(ctx);
                  AnnotationSheet.showGlossary(context, chapter.glossary);
                },
              ),
            if (chapter.cast.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const Text('本幕人物'),
                onTap: () {
                  Navigator.pop(ctx);
                  AnnotationSheet.showCast(context, chapter.cast);
                },
              ),
            ListTile(
              leading: const Icon(Icons.data_object_rounded),
              title: const Text('查看原始输出'),
              subtitle: Text(
                chapter.rawOutput.isEmpty
                    ? '本幕没有留存原始输出'
                    : '模型返回的原文，用于排查格式问题',
              ),
              enabled: chapter.rawOutput.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                _showRawOutput(chapter);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyChapter(ChapterNode chapter) async {
    final sb = StringBuffer();
    sb.writeln(chapter.date.trim().isEmpty
        ? chapter.title
        : '${chapter.title} · ${chapter.date.trim()}');
    final act = chapter.playerAction;
    if (act != null && act.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('【你的行动】${act.trim()}');
    }
    if (chapter.content.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln(chapter.content.trim());
    }
    await Clipboard.setData(ClipboardData(text: sb.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本幕已复制到剪贴板')),
    );
  }

  /// 排障用：直接把模型返回的原文摊开。
  /// 「为什么这次 cast 又漏了」——不用再猜，看一眼就知道。
  void _showRawOutput(ChapterNode chapter) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '模型原始输出',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: chapter.rawOutput),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('原始输出已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      chapter.rawOutput,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionCard(ThemeData theme, String act) {
    final palette = AppTheme.readingOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
        border: Border(
          left: BorderSide(color: palette.accent, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '【你的行动】 ',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
          ),
          Expanded(
            child: Text(
              act,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveView(ThemeData theme, double fontSize) {
    final palette = AppTheme.readingOf(context);
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
                      AlwaysStoppedAnimation<Color>(palette.accent),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _degraded ? '本地降级中…' : '推演中…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ],
          ),
        ),
        if (preview.isNotEmpty)
          Text(
            '${TextLayout.indent(_config.paragraphIndent)}$preview',
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontSize: fontSize,
              height: _config.lineHeight,
              letterSpacing: 0.4,
              color: palette.ink,
            ),
          ),
      ],
    );
  }

  Widget _noticeView(ThemeData theme) {
    final palette = AppTheme.readingOf(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.rule),
      ),
      child: Text(
        _notice,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: palette.ink,
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
