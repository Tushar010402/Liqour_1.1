import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_colors.dart';
import '../constants/animation_constants.dart';
import '../models/ai_feedback_model.dart';
import '../utils/haptic_feedback.dart';

const _kStorageKey = 'ai_feedback_entries';
const _kMaxEntries = 100;

const _kCommonTags = ['Accurate', 'Fast', 'Easy to use'];

const _kStarGold = Color(0xFFFBBF24);
const _kUnselected = Color(0xFFD0D5DD);

class AIFeedbackBottomSheet extends StatefulWidget {
  final AIFlowType flowType;
  final String successMessage;

  const AIFeedbackBottomSheet({
    super.key,
    required this.flowType,
    required this.successMessage,
  });

  /// Show the feedback bottom sheet and await user action.
  static Future<void> show(
    BuildContext context, {
    required AIFlowType flowType,
    required String successMessage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AIFeedbackBottomSheet(
        flowType: flowType,
        successMessage: successMessage,
      ),
    );
  }

  @override
  State<AIFeedbackBottomSheet> createState() => _AIFeedbackBottomSheetState();
}

class _AIFeedbackBottomSheetState extends State<AIFeedbackBottomSheet>
    with TickerProviderStateMixin {
  int _rating = 0;
  final Set<String> _selectedTags = {};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  // Animations
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;
  late final AnimationController _starsController;
  late final AnimationController _chipsController;

  @override
  void initState() {
    super.initState();

    // Checkmark animation — elastic scale-in
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );

    // Stars stagger controller (drives all 5 stars)
    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450), // 5 * 50ms stagger + 200ms each
    );

    // Chips fade-in
    _chipsController = AnimationController(
      vsync: this,
      duration: AnimationConstants.standard,
    );

    // Kick off sequence
    _runEntryAnimation();
  }

  Future<void> _runEntryAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    HapticFeedbackUtil.success();
    _checkController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _starsController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _chipsController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _starsController.dispose();
    _chipsController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  List<String> get _allTags => [..._kCommonTags, ...widget.flowType.specificTags];

  // ── Persistence ──

  Future<void> _saveFeedback() async {
    final entry = AIFeedbackEntry(
      id: const Uuid().v4(),
      flowType: widget.flowType.key,
      rating: _rating,
      tags: _selectedTags.toList(),
      comment: _commentController.text.trim().isNotEmpty
          ? _commentController.text.trim()
          : null,
      timestamp: DateTime.now(),
    );

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kStorageKey) ?? [];
    existing.add(entry.toJsonString());

    // FIFO eviction
    if (existing.length > _kMaxEntries) {
      existing.removeRange(0, existing.length - _kMaxEntries);
    }

    await prefs.setStringList(_kStorageKey, existing);
  }

  Future<void> _onSubmit() async {
    if (_rating == 0 || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedbackUtil.submit();
    await _saveFeedback();
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _onSkip() {
    Navigator.pop(context);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDragHandle(),
                const SizedBox(height: 20),
                _buildCheckmark(),
                const SizedBox(height: 16),
                _buildTitle(),
                const SizedBox(height: 4),
                _buildSubtitle(),
                const SizedBox(height: 24),
                _buildRatingPrompt(),
                const SizedBox(height: 12),
                _buildStars(),
                const SizedBox(height: 20),
                _buildChips(),
                const SizedBox(height: 16),
                _buildCommentField(),
                const SizedBox(height: 20),
                _buildSubmitButton(),
                const SizedBox(height: 4),
                _buildSkipButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: _kUnselected,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildCheckmark() {
    return ScaleTransition(
      scale: _checkScale,
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      widget.flowType.title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSubtitle() {
    return Text(
      widget.successMessage,
      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildRatingPrompt() {
    return const Text(
      'How was the AI experience?',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildStars() {
    return AnimatedBuilder(
      animation: _starsController,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            // Stagger: each star starts at i*0.1 of the overall animation
            final starProgress = ((_starsController.value - i * 0.1) / 0.6).clamp(0.0, 1.0);
            final isFilled = i < _rating;

            return GestureDetector(
              onTap: () {
                HapticFeedbackUtil.selectionClick();
                setState(() => _rating = i + 1);
              },
              child: Opacity(
                opacity: starProgress,
                child: Transform.scale(
                  scale: 0.5 + starProgress * 0.5,
                  child: AnimatedScale(
                    scale: isFilled ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.elasticOut,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 36,
                        color: isFilled ? _kStarGold : _kUnselected,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildChips() {
    return FadeTransition(
      opacity: _chipsController,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _allTags.map((tag) {
          final selected = _selectedTags.contains(tag);
          return FilterChip(
            label: Text(tag),
            selected: selected,
            onSelected: (val) {
              HapticFeedbackUtil.selectionClick();
              setState(() {
                if (val) {
                  _selectedTags.add(tag);
                } else {
                  _selectedTags.remove(tag);
                }
              });
            },
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            checkmarkColor: AppColors.primary,
            labelStyle: TextStyle(
              color: selected ? AppColors.primary : Colors.grey.shade700,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected ? AppColors.primary : _kUnselected,
              ),
            ),
            backgroundColor: Colors.white,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCommentField() {
    return TextField(
      controller: _commentController,
      maxLines: 3,
      minLines: 1,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: 'Tell us more (optional)...',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kUnselected),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kUnselected),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final enabled = _rating > 0 && !_isSubmitting;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? _onSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Submit Feedback',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return TextButton(
      onPressed: _isSubmitting ? null : _onSkip,
      child: Text(
        'Skip',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
