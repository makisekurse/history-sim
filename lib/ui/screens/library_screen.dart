import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../data/world_book_repository.dart';
import '../../models/app_config.dart';
import '../../models/chapter_node.dart';
import '../../models/save_slot.dart';
import '../../models/world_book.dart';
import '../../services/save_service.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'worldbook_editor_screen.dart';

/// 首页：推演存档 + 世界书。
///
/// 应用不内置任何世界书 —— 第一次打开时这里是空的，
/// 需要先新建或导入一本世界书，才能开始推演。
class LibraryScreen extends StatefulWidget {
  final AppConfig config;
  final ValueChanged<AppConfig> onConfigChanged;

  const LibraryScreen({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<SaveSlot> _slots = <SaveSlot>[];
  List<WorldBook> _books = <WorldBook>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final slots = await SaveService.loadAll();
    final books = await WorldBookRepository.loadAll();
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _books = books;
      _loading = false;
    });
  }

  // ---------- 新建推演 ----------

  Future<void> _newSession() async {
    if (_books.isEmpty) {
      _toast('还没有世界书。先新建或导入一本，才能开始推演。');
      _tab.animateTo(1);
      return;
    }

    final book = await showModalBottomSheet<WorldBook>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('选择世界书', style: TextStyle(fontSize: 14)),
            ),
            for (final b in _books)
              ListTile(
                title: Text(b.name, style: const TextStyle(fontSize: 14.5)),
                subtitle: b.era.trim().isEmpty
                    ? null
                    : Text(b.era, style: const TextStyle(fontSize: 12)),
                trailing: b.isPlayable
                    ? null
                    : const Icon(Icons.warning_amber_rounded, size: 18),
                onTap: () => Navigator.pop(ctx, b),
              ),
          ],
        ),
      ),
    );
    if (book == null) return;

    if (!book.isPlayable) {
      _toast('这本世界书还缺：${book.missingFields.join('、')}');
      await _editBook(book);
      return;
    }

    final slot = SaveSlot(
      id: SaveSlot.newId(),
      title: book.name,
      worldBook: book,
    );

    // 世界书自带开篇就直接落第一幕，省一次模型调用，也让作者掌控开场。
    if (book.openingScene.trim().isNotEmpty) {
      slot.history = <ChapterNode>[
        ChapterNode(
          chapterIndex: 1,
          title: '第一幕',
          content: book.openingScene.trim(),
          date: book.era.trim(),
          choices: book.openingChoices,
        ),
      ];
    }

    await SaveService.upsert(slot);
    await _reload();
    if (!mounted) return;
    await _openReader(slot);
  }

  Future<void> _openReader(SaveSlot slot) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          config: widget.config,
          slot: slot,
          onConfigChanged: widget.onConfigChanged,
        ),
      ),
    );
    await _reload();
  }

  // ---------- 世界书管理 ----------

  Future<void> _editBook(WorldBook book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<WorldBook>(
        builder: (_) => WorldBookEditorScreen(book: book),
      ),
    );
    await _reload();
  }

  Future<void> _createBook() async {
    final book = WorldBook.blank();
    await WorldBookRepository.upsert(book);
    await _reload();
    if (!mounted) return;
    await _editBook(book);
  }

  Future<void> _importBook() async {
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('导入世界书', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              '粘贴世界书的 JSON，或直接粘贴一段世界观提示词文本。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(ctx)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 8,
              minLines: 5,
              decoration: const InputDecoration(
                hintText: '{"name":"…","worldview":"…","playerRole":"…"}',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      ctrl.text = data?.text ?? '';
                    },
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('从剪贴板读取'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('导入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (text == null || text.trim().isEmpty) return;

    try {
      final book = WorldBook.fromImportText(text);
      await WorldBookRepository.upsert(book);
      await _reload();
      if (!mounted) return;
      _toast('已导入《${book.name}》');
      await _editBook(book);
    } catch (e) {
      if (!mounted) return;
      _toast('导入失败：$e');
    }
  }

  Future<void> _bookMenu(WorldBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _editBook(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制一份'),
              onTap: () async {
                Navigator.pop(ctx);
                final copy = book.copyWith(name: '${book.name} 副本');
                final fresh = WorldBook(
                  id: WorldBook.newId(),
                  name: copy.name,
                  era: copy.era,
                  worldview: copy.worldview,
                  playerRole: copy.playerRole,
                  narrativeStyle: copy.narrativeStyle,
                  extraRules: copy.extraRules,
                  openingScene: copy.openingScene,
                  openingChoices: copy.openingChoices,
                );
                await WorldBookRepository.upsert(fresh);
                await _reload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出 JSON 到剪贴板'),
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(
                  ClipboardData(text: book.exportToJson()),
                );
                if (mounted) _toast('已复制到剪贴板');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm('删除世界书《${book.name}》？');
                if (!ok) return;
                await WorldBookRepository.delete(book.id);
                await _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 存档管理 ----------

  Future<void> _slotMenu(SaveSlot slot) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出存档到剪贴板'),
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(
                  ClipboardData(text: SaveService.exportSlot(slot)),
                );
                if (mounted) _toast('存档 JSON 已复制到剪贴板');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除这一局'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm('删除《${slot.title}》这一局？');
                if (!ok) return;
                await SaveService.delete(slot.id);
                await _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppInfo.appName),
        actions: <Widget>[
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    config: widget.config,
                    onConfigChanged: widget.onConfigChanged,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: theme.colorScheme.primary,
          indicatorColor: theme.colorScheme.primary,
          tabs: const <Widget>[
            Tab(text: '推演'),
            Tab(text: '世界书'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: <Widget>[_slotsTab(theme), _booksTab(theme)],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tab.index == 0 ? _newSession() : _createBook(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_tab.index == 0 ? '新建推演' : '新建世界书'),
      ),
    );
  }

  Widget _slotsTab(ThemeData theme) {
    if (_slots.isEmpty) {
      return _empty(
        theme,
        '还没有进行中的推演',
        '先到「世界书」里新建或导入一本世界书，然后点右下角开始。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _slots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = _slots[i];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openReader(s),
          onLongPress: () => _slotMenu(s),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  s.summaryLine,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _booksTab(ThemeData theme) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importBook,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('导入提示词 / JSON'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: theme.dividerColor),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_books.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
          child: _empty(
            theme,
            '还没有世界书',
            '世界书决定你演谁、在什么时代、用什么文风。\n'
            '点右下角新建一本，或从别处导入一段提示词。',
          ),
        ),
      for (final b in _books)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _editBook(b),
            onLongPress: () => _bookMenu(b),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (!b.isPlayable)
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                  if (b.era.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      b.era,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (b.playerRole.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      '扮演：${b.playerRole}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 96),
    ];

    return ListView(children: children);
  }

  Widget _empty(ThemeData theme, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.75,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
}
