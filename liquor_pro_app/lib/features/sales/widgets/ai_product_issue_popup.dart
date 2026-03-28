import 'package:flutter/material.dart';
import '../models/daily_sales_models.dart';

/// Language options for AI text
enum AILanguage { english, hinglish }

/// Simple, clean popup to show AI validation issues for a single product
/// Supports English and Hinglish language toggle
class AIProductIssuePopup extends StatefulWidget {
  final ItemInsight insight;
  final VoidCallback? onClose;

  const AIProductIssuePopup({
    super.key,
    required this.insight,
    this.onClose,
  });

  /// Show as a modal bottom sheet
  static Future<void> show(BuildContext context, ItemInsight insight) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AIProductIssuePopup(
        insight: insight,
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  State<AIProductIssuePopup> createState() => _AIProductIssuePopupState();
}

class _AIProductIssuePopupState extends State<AIProductIssuePopup> {
  AILanguage _language = AILanguage.hinglish; // Default Hinglish

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor();
    final statusIcon = _getStatusIcon();
    final statusText = _getStatusText();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with language toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  statusColor.withOpacity(0.15),
                  statusColor.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Top row: Language toggle + Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Language toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLanguageChip('EN', AILanguage.english),
                          _buildLanguageChip('HI', AILanguage.hinglish),
                        ],
                      ),
                    ),
                    // Close button
                    GestureDetector(
                      onTap: widget.onClose ?? () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Product name
                Text(
                  widget.insight.productName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Match confidence
                Text(
                  '${widget.insight.matchConfidence.toStringAsFixed(0)}% ${_t('match')}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),

          // Issues list
          if (widget.insight.hasIssues)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section header
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: Colors.purple[600]),
                      const SizedBox(width: 8),
                      Text(
                        _t('ai_found_issues'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Issues
                  ...widget.insight.issues.map((issue) => _buildIssueCard(issue)),
                ],
              ),
            )
          else
            // Matched - no issues
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Color(0xFF34C759),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t('all_correct'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('matches_receipt'),
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // Bottom padding
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLanguageChip(String label, AILanguage lang) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _language == lang;
    return GestureDetector(
      onTap: () => setState(() => _language = lang),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? cs.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildIssueCard(AIIssue issue) {
    final cs = Theme.of(context).colorScheme;
    final isCritical = issue.isCritical;
    final color = isCritical ? const Color(0xFFFF3B30) : const Color(0xFFFF9500);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Issue type header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCritical ? Icons.cancel : Icons.warning_amber,
                      color: color,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getIssueTypeText(issue.type),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Message
          Text(
            _getIssueMessage(issue),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.3,
            ),
          ),

          // Value comparison
          if (issue.enteredValue.isNotEmpty || issue.ocrValue.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Entered value
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _t('you_entered').toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withOpacity(0.3)),
                          ),
                          child: Text(
                            issue.enteredValue.isNotEmpty ? issue.enteredValue : '-',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.arrow_forward,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),

                  // OCR value
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _t('receipt_shows').toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3)),
                          ),
                          child: Text(
                            issue.ocrValue.isNotEmpty ? issue.ocrValue : '-',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF34C759),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Suggestion
          if (issue.suggestion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb, size: 14, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _getSuggestion(issue),
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============ TRANSLATION HELPERS ============

  /// Get translated text based on current language
  String _t(String key) {
    final isHinglish = _language == AILanguage.hinglish;

    final translations = <String, Map<AILanguage, String>>{
      'match': {
        AILanguage.english: 'Match',
        AILanguage.hinglish: 'Match',
      },
      'ai_found_issues': {
        AILanguage.english: 'AI found these issues:',
        AILanguage.hinglish: 'AI ne ye galtiyan paayi:',
      },
      'all_correct': {
        AILanguage.english: 'All Correct!',
        AILanguage.hinglish: 'Sab Sahi Hai!',
      },
      'matches_receipt': {
        AILanguage.english: 'Matches with receipt',
        AILanguage.hinglish: 'Receipt se match ho gaya',
      },
      'you_entered': {
        AILanguage.english: 'You Entered',
        AILanguage.hinglish: 'Tune Likha',
      },
      'receipt_shows': {
        AILanguage.english: 'Receipt Shows',
        AILanguage.hinglish: 'Receipt Pe',
      },
    };

    return translations[key]?[_language] ?? key;
  }

  Color _getStatusColor() {
    if (widget.insight.isCritical) return const Color(0xFFFF3B30);
    if (widget.insight.isWarning) return const Color(0xFFFF9500);
    if (widget.insight.isMatched) return const Color(0xFF34C759);
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  IconData _getStatusIcon() {
    if (widget.insight.isCritical) return Icons.cancel;
    if (widget.insight.isWarning) return Icons.warning_amber;
    if (widget.insight.isMatched) return Icons.check_circle;
    return Icons.help;
  }

  String _getStatusText() {
    final isHinglish = _language == AILanguage.hinglish;
    if (widget.insight.isCritical) {
      return isHinglish ? 'GALAT' : 'INCORRECT';
    }
    if (widget.insight.isWarning) {
      return isHinglish ? 'CHECK KARO' : 'NEEDS CHECK';
    }
    if (widget.insight.isMatched) {
      return isHinglish ? 'SAHI' : 'CORRECT';
    }
    return 'UNKNOWN';
  }

  String _getIssueTypeText(String type) {
    final isHinglish = _language == AILanguage.hinglish;
    switch (type.toLowerCase()) {
      case 'quantity':
        return isHinglish ? 'QUANTITY GALAT' : 'WRONG QUANTITY';
      case 'price':
        return isHinglish ? 'PRICE GALAT' : 'WRONG PRICE';
      case 'missing':
        return isHinglish ? 'NAHI MILA' : 'NOT FOUND';
      case 'extra':
        return isHinglish ? 'EXTRA HAI' : 'EXTRA ITEM';
      default:
        return type.toUpperCase();
    }
  }

  String _getIssueMessage(AIIssue issue) {
    final isHinglish = _language == AILanguage.hinglish;
    final type = issue.type.toLowerCase();

    switch (type) {
      case 'quantity':
        if (isHinglish) {
          return 'Quantity match nahi ho rahi - tune ${issue.enteredValue} likha lekin receipt pe ${issue.ocrValue} hai';
        }
        return 'Quantity mismatch - you entered ${issue.enteredValue} but receipt shows ${issue.ocrValue}';
      case 'price':
        if (isHinglish) {
          return 'Price galat hai - check karo ki sahi rate laga hai ya nahi';
        }
        return 'Price mismatch - verify if the correct rate is applied';
      default:
        return issue.message.isNotEmpty
            ? issue.message
            : (isHinglish ? 'Kuch galat hai is item mein' : 'There is an issue with this item');
    }
  }

  String _getSuggestion(AIIssue issue) {
    final isHinglish = _language == AILanguage.hinglish;
    final type = issue.type.toLowerCase();

    switch (type) {
      case 'quantity':
        return isHinglish
            ? 'Receipt dekh ke sahi quantity enter karo'
            : 'Check receipt and enter correct quantity';
      case 'price':
        return isHinglish
            ? 'Price list ya receipt se verify karo'
            : 'Verify from price list or receipt';
      default:
        return issue.suggestion.isNotEmpty
            ? issue.suggestion
            : (isHinglish ? 'Entry dobara check karo' : 'Please verify the entry');
    }
  }
}
