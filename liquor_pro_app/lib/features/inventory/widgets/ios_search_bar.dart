import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import '../../../core/constants/app_text_styles.dart';

/// Search bar matching JSX SearchBar design.
/// JSX: #F2F3F6 bg, radius 14, padding "13px 16px", search icon + hint "Search products...",
/// AI label on right side, filter button (48x48, #E8EDF3, filter icon #0D47A1)
class IOSSearchBar extends StatefulWidget {
  final String? hint;
  final Function(String) onSearch;
  final VoidCallback? onClear;
  final Duration debounce;
  final bool autofocus;

  const IOSSearchBar({
    super.key,
    this.hint = 'Search products...',
    required this.onSearch,
    this.onClear,
    this.debounce = const Duration(milliseconds: 500),
    this.autofocus = false,
  });

  @override
  State<IOSSearchBar> createState() => _IOSSearchBarState();
}

class _IOSSearchBarState extends State<IOSSearchBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  bool _isFocused = false;
  late AnimationController _animationController;
  late Animation<double> _cancelButtonAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _cancelButtonAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _focusNode.addListener(_onFocusChange);

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });

    if (_isFocused) {
      _animationController.forward();
    } else {
      if (_controller.text.isEmpty) {
        _animationController.reverse();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(widget.debounce, () {
      widget.onSearch(query);
    });
  }

  void _clearSearch() {
    _controller.clear();
    widget.onSearch('');
    widget.onClear?.call();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Search Field — JSX: #F2F3F6 bg, radius 14, gap 10
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: _isFocused ? Colors.white : const Color(0xFFF2F3F6),
                borderRadius: BorderRadius.circular(14),
                border: _isFocused
                    ? Border.all(color: const Color(0xFF0D47A1), width: 1.5)
                    : null,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onSearchChanged,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF1A1A2E),
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFFAAAAAA),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(
                    CupertinoIcons.search,
                    color: Color(0xFFAAAAAA),
                    size: 20,
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Color(0xFFAAAAAA),
                            size: 18,
                          ),
                          onPressed: _clearSearch,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            'AI',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: const Color(0xFF666666).withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 20),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Filter button — JSX: 48x48, #E8EDF3 bg, radius 12, filter icon #0D47A1
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.sort_rounded, color: Color(0xFF0D47A1), size: 22),
          ),

          // Cancel Button (slides in when focused)
          SizeTransition(
            sizeFactor: _cancelButtonAnimation,
            axis: Axis.horizontal,
            axisAlignment: -1,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _clearSearch, minimumSize: Size.zero,
                child: Text(
                  'Cancel',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFF0D47A1),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
