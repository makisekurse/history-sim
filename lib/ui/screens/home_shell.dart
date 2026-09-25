import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../data/prefs_store.dart';
import '../../data/world_book_repository.dart';
import '../../models/app_config.dart';
import '../../models/chapter_node.dart';
import '../../models/save_slot.dart';
import '../../models/world_book.dart';
import '../../services/save_service.dart';
import 'about_screen.dart';
import 'continue_tab.dart';
import 'profile_tab.dart';
import 'quick_create_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'worldbook_editor_screen.dart';
import 'worlds_tab.dart';

/// 主壳：世界 · 继续 · 我的。
///
/// 用户脑子里的三件事：
/// - 世界 = 我创造什么
/// - 继续 = 我正在经历什么
/// - 我的 = App 设置
class HomeShell extends StatefulWidget {
  final AppConfig config;
  final ValueChanged<AppConfig> onConfigChanged;

  const HomeShell({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const String _kActiveSlot = 'nijing_active_slot';

  int _index = 1; // 默认落在「继续」：用户最想做的事是接着玩

  List<SaveSlot> _slots = <SaveSlot>[];
  List<WorldBook> _books = <WorldBook>[];
  /// 回滚前自动生成的备份。**不计入推演数量**。
  List<SaveSlot> _backups = <SaveSlot>[];
  String? _activeSlotId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final slots = await SaveService.loadAll();
    final books = await WorldBookRepository.loadAll();
    final backups = await SaveService.loadBackups();
    final active = await PrefsStore.getString(_kActiveSlot);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _books = books;
      _backups = backups;
      _activeSlotId = active;
      _loading = false;
    });
  }

  Future<void> _setActiveSlot(String id) async {
    _activeSlotId = id;
    await PrefsStore.setString(_kActiveSlot, id);
  }

  // ---------- 进入世界 ----------

  Future<void> _newSession() async {
    if (_books.isEmpty) {
      _toast('还没有世界。先创建或导入一个，才能进入。');
      setState(() => _index = 0);
      return;
    }
    final playable = _books.where((b) => b.isPlayable).toList();
    if (playable.isEmpty) {
      _toast('现有的世界书还缺必填项，先补全一个。');
      setState(() => _index = 0);
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
              child: Text('选择要进入的世界', style: TextStyle(fontSize: 14)),
            ),
            for (final b in playable)
              ListTile(
                title: Text(b.name, style: const TextStyle(fontSize: 14.5)),
                subtitle: b.era.trim().isEmpty
                    ? null
                    : Text(b.era, style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, b),
              ),
          ],
        ),
      ),
    );
    if (book == null) return;

    await _startSessionWith(book);
  }

  Future<void> _startSessionWith(WorldBook book) async {
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
    await _setActiveSlot(slot.id);
    await _reload();
    if (!mounted) return;
    await _openReader(slot);
  }

  Future<void> _openReader(SaveSlot slot) async {
    await _setActiveSlot(slot.id);
    if (!mounted) return;
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

  // ---------- 世界书 ----------

  Future<void> _editBook(WorldBook book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<WorldBook>(
        builder: (_) => WorldBookEditorScreen(book: book),
      ),
    );
    await _reload();
  }

  Future<void> _createBook() async {
    final theme = Theme.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('快速创建'),
              subtitle: const Text('一句话描述，AI 扩写成完整设定（生成后可改）'),
              onTap: () => Navigator.pop(ctx, 'quick'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('手动编写'),
              subtitle: const Text('从空白模板开始，逐项自己填'),
              onTap: () => Navigator.pop(ctx, 'blank'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'quick') {
      await Navigator.of(context).push<WorldBook>(
        MaterialPageRoute<WorldBook>(
          builder: (_) => QuickCreateScreen(config: widget.config),
        ),
      );
      await _reload();
      return;
    }

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
                color:
                    Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
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
                    label: const Text('读剪贴板'),
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
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('进入这个世界'),
              enabled: book.isPlayable,
              onTap: () {
                Navigator.pop(ctx);
                _startSessionWith(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _editBook(book);
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

  // ---------- 存档 ----------

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
                if (_activeSlotId == slot.id) {
                  await PrefsStore.remove(_kActiveSlot);
                  _activeSlotId = null;
                }
                await _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 数据管理 ----------

  Future<void> _dataManage() async {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '本机数据',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 数量分开列 —— 回滚备份不是「推演」，
                  // 混在一起会让用户以为凭空多出了几局。
                  Text(
                    '世界书 ${_books.length} 本 · 推演 ${_slots.length} 个',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _backups.isEmpty
                        ? '世界书与存档只保存在本机，不会上传。'
                        : '另有 ${_backups.length} 份回滚备份（回滚前自动生成，不计入推演）。',
                    style: TextStyle(fontSize: 11.5, height: 1.6, color: muted),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出全部世界书到剪贴板'),
              enabled: _books.isNotEmpty,
              onTap: () async {
                Navigator.pop(ctx);
                final all = _books
                    .map((b) => b.exportToJson())
                    .join('\n\n=====\n\n');
                await Clipboard.setData(ClipboardData(text: all));
                if (mounted) _toast('已复制 ${_books.length} 本世界书');
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出全部推演存档到剪贴板'),
              enabled: _slots.isNotEmpty,
              onTap: () async {
                Navigator.pop(ctx);
                final all = _slots
                    .map((s) => SaveService.exportSlot(s))
                    .join('\n\n=====\n\n');
                await Clipboard.setData(ClipboardData(text: all));
                if (mounted) _toast('已复制 ${_slots.length} 个推演存档');
              },
            ),
            if (_backups.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清理回滚备份'),
                subtitle: Text('删除 ${_backups.length} 份自动备份，不影响推演进度'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirm(
                    '删除 ${_backups.length} 份回滚备份？'
                    '推演进度不受影响，但之后无法再回到回滚前的分支。',
                  );
                  if (!ok) return;
                  final remaining =
                      (await SaveService.loadAll(includeBackups: true))
                          .where((s) => !s.isBackup)
                          .toList();
                  await SaveService.saveAll(remaining);
                  await _reload();
                  if (mounted) _toast('已清理回滚备份');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空全部数据'),
              subtitle: const Text('世界书、存档、备份、API Key 全部删除，不可恢复'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await _confirm(
                  '确定清空全部数据？世界书、存档、备份与 API Key 都会被删除，无法恢复。',
                );
                if (!ok) return;
                await SaveService.saveAll(<SaveSlot>[]);
                await WorldBookRepository.saveAll(<WorldBook>[]);
                await PrefsStore.remove(_kActiveSlot);
                await _reload();
                if (mounted) _toast('已清空');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _index,
                children: <Widget>[
                  WorldsTab(
                    books: _books,
                    onCreate: _createBook,
                    onImport: _importBook,
                    onEdit: _editBook,
                    onMenu: _bookMenu,
                    onStartSession: _startSessionWith,
                  ),
                  ContinueTab(
                    slots: _slots,
                    activeSlotId: _activeSlotId,
                    onOpen: _openReader,
                    onMenu: _slotMenu,
                    onNewSession: _newSession,
                  ),
                  ProfileTab(
                    onOpenSection: (section) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          config: widget.config,
                          onConfigChanged: widget.onConfigChanged,
                          section: section,
                        ),
                      ),
                    ),
                    onOpenAbout: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AboutScreen(),
                      ),
                    ),
                    onDataManage: _dataManage,
                    versionLabel: AppInfo.versionLabel,
                    worldCountLabel: '${_books.length} 本世界书',
                    slotCountLabel: '${_slots.length} 个推演',
                  ),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: theme.scaffoldBackgroundColor,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.14),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: '世界',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '继续',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
