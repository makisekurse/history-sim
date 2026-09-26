import 'package:flutter/material.dart';

/// 自由意志输入栏。
///
/// - 支持「主宰模式（最高权限）」实时切换，左侧醒目展示权威图标（金光高亮）；
/// - 支持外部托管 [controller] 与 [focusNode]，彻底杜绝滚动及重构导致的草稿丢失；
/// - 生成中时变成「中止」按钮 —— 随时可安全中断。
class FreeInputBar extends StatefulWidget {
  final bool busy;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool godMode;
  final ValueChanged<bool>? onToggleGodMode;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  const FreeInputBar({
    super.key,
    required this.busy,
    this.controller,
    this.focusNode,
    this.godMode = false,
    this.onToggleGodMode,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<FreeInputBar> createState() => _FreeInputBarState();
}

class _FreeInputBarState extends State<FreeInputBar> {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void dispose() {
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _effectiveController.text.trim();
    if (text.isEmpty) return;
    _effectiveController.clear();
    _effectiveFocusNode.unfocus();
    widget.onSend(text);
  }

  static const Color _kGodGold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (widget.busy) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('中止本次推演'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: theme.dividerColor),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      );
    }

    final isGod = widget.godMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isGod ? _kGodGold : theme.dividerColor,
          width: isGod ? 1.6 : 1.0,
        ),
        boxShadow: isGod
            ? <BoxShadow>[
                BoxShadow(
                  color: _kGodGold.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          // 左侧主宰模式切换按钮
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 6),
            child: Tooltip(
              message: isGod ? '主宰模式已开启（点击临时关闭）' : '主宰模式（点击开启绝对权限）',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onToggleGodMode == null
                    ? null
                    : () => widget.onToggleGodMode!(!isGod),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isGod
                        ? _kGodGold.withValues(alpha: 0.2)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isGod ? _kGodGold : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isGod ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                    size: 19,
                    color: isGod
                        ? _kGodGold
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _effectiveController,
              focusNode: _effectiveFocusNode,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: isGod
                    ? '【主宰模式】写下你规定的世界走向，AI 将绝对服从…'
                    : '也可以自己写一句行动，例如「密电刘文辉，陈明大势」',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isGod
                      ? _kGodGold.withValues(alpha: 0.75)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: IconButton(
              onPressed: _submit,
              icon: Icon(isGod ? Icons.bolt_rounded : Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: isGod
                    ? _kGodGold.withValues(alpha: 0.22)
                    : primary.withValues(alpha: 0.12),
                foregroundColor: isGod ? _kGodGold : primary,
              ),
              tooltip: isGod ? '敕令执行' : '执行',
            ),
          ),
        ],
      ),
    );
  }
}
