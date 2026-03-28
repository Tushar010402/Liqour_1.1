import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Inline quantity editor with smooth animations
///
/// Features:
/// - Direct text input for quick changes
/// - Smooth scale animations
/// - Haptic feedback on interactions
/// - Debounced auto-save (500ms)
/// - Min/max validation
class QuantityEditor extends StatefulWidget {
  final int initialQuantity;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;

  const QuantityEditor({
    super.key,
    required this.initialQuantity,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.compact = false,
  });

  @override
  State<QuantityEditor> createState() => _QuantityEditorState();
}

class _QuantityEditorState extends State<QuantityEditor>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  Timer? _debounceTimer;
  int _currentQuantity = 0;
  bool _isEditing = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentQuantity = widget.initialQuantity;
    _controller = TextEditingController(text: _currentQuantity.toString());

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() => _isEditing = true);
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      } else {
        setState(() => _isEditing = false);
        _validateAndUpdate();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _pulseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateQuantity(int newValue) {
    if (newValue < widget.min || newValue > widget.max) return;

    setState(() {
      _currentQuantity = newValue;
      _controller.text = newValue.toString();
    });

    // Animate pulse
    _pulseController.forward().then((_) => _pulseController.reverse());

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Debounced callback
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onChanged(newValue);
    });
  }

  void _validateAndUpdate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _controller.text = _currentQuantity.toString();
      return;
    }

    final newValue = int.tryParse(text);
    if (newValue == null) {
      _controller.text = _currentQuantity.toString();
      return;
    }

    final clampedValue = newValue.clamp(widget.min, widget.max);
    if (clampedValue != _currentQuantity) {
      _updateQuantity(clampedValue);
    } else {
      _controller.text = _currentQuantity.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: _buildQuantityDisplay(context),
    );
  }

  Widget _buildQuantityDisplay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        minWidth: widget.compact ? 50 : 60,
        maxWidth: widget.compact ? 80 : 100,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 12,
        vertical: widget.compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: _isEditing
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isEditing ? cs.primary : cs.outlineVariant,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        style: TextStyle(
          fontSize: widget.compact ? 14 : 16,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) {
          _validateAndUpdate();
          _focusNode.unfocus();
        },
      ),
    );
  }
}
