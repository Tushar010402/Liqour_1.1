import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard Shortcuts Handler
///
/// PHASE 5.4: Power User Keyboard Shortcuts
/// Enable keyboard navigation for desktop and iPad with external keyboards
///
/// SHORTCUTS:
/// - A: Accept current item
/// - R: Reject current item
/// - Space: Next item
/// - E: Expand details
/// - Cmd/Ctrl + Z: Undo
/// - Cmd/Ctrl + Shift + Z: Redo
/// - Escape: Close modal/cancel
/// - Arrow Up/Down: Navigate items
///
/// USAGE:
/// ```dart
/// KeyboardShortcutsHandler(
///   onAccept: () => acceptItem(),
///   onReject: () => rejectItem(),
///   onUndo: () => undo(),
///   onRedo: () => redo(),
///   child: YourWidget(),
/// )
/// ```

class KeyboardShortcutsHandler extends StatefulWidget {
  final Widget child;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onExpand;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onEscape;
  final bool enabled;

  const KeyboardShortcutsHandler({
    super.key,
    required this.child,
    this.onAccept,
    this.onReject,
    this.onNext,
    this.onPrevious,
    this.onExpand,
    this.onUndo,
    this.onRedo,
    this.onEscape,
    this.enabled = true,
  });

  @override
  State<KeyboardShortcutsHandler> createState() =>
      _KeyboardShortcutsHandlerState();
}

class _KeyboardShortcutsHandlerState extends State<KeyboardShortcutsHandler> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus when widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.enabled) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled) return false;
    if (event is! KeyDownEvent) return false;

    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isModifierPressed = isMetaPressed || isControlPressed;

    // Cmd/Ctrl + Shift + Z: Redo
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.onRedo?.call();
      return true;
    }

    // Cmd/Ctrl + Z: Undo
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.onUndo?.call();
      return true;
    }

    // No modifier keys for remaining shortcuts
    if (isModifierPressed) return false;

    switch (event.logicalKey) {
      // A: Accept
      case LogicalKeyboardKey.keyA:
        widget.onAccept?.call();
        return true;

      // R: Reject
      case LogicalKeyboardKey.keyR:
        widget.onReject?.call();
        return true;

      // E: Expand
      case LogicalKeyboardKey.keyE:
        widget.onExpand?.call();
        return true;

      // Space: Next
      case LogicalKeyboardKey.space:
        widget.onNext?.call();
        return true;

      // Arrow Down: Next
      case LogicalKeyboardKey.arrowDown:
        widget.onNext?.call();
        return true;

      // Arrow Up: Previous
      case LogicalKeyboardKey.arrowUp:
        widget.onPrevious?.call();
        return true;

      // Escape: Cancel/Close
      case LogicalKeyboardKey.escape:
        widget.onEscape?.call();
        return true;

      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.enabled,
      onKeyEvent: (node, event) {
        final handled = _handleKeyEvent(event);
        return handled ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}

/// Keyboard Shortcuts Info Widget
///
/// Displays available keyboard shortcuts to users
class KeyboardShortcutsInfo extends StatelessWidget {
  const KeyboardShortcutsInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.keyboard_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Keyboard Shortcuts'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Navigation',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildShortcutRow(context, 'A', 'Accept current item'),
            _buildShortcutRow(context, 'R', 'Reject current item'),
            _buildShortcutRow(context, 'E', 'Expand details'),
            _buildShortcutRow(context, 'Space', 'Next item'),
            _buildShortcutRow(context, '↑', 'Previous item'),
            _buildShortcutRow(context, '↓', 'Next item'),
            const SizedBox(height: 16),
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildShortcutRow(context, 'Cmd/Ctrl + Z', 'Undo'),
            _buildShortcutRow(context, 'Cmd/Ctrl + Shift + Z', 'Redo'),
            _buildShortcutRow(context, 'Esc', 'Cancel/Close'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it!'),
        ),
      ],
    );
  }

  Widget _buildShortcutRow(BuildContext context, String key, String description) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cs.onSurfaceVariant),
            ),
            child: Text(
              key,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Show keyboard shortcuts dialog
void showKeyboardShortcuts(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const KeyboardShortcutsInfo(),
  );
}
