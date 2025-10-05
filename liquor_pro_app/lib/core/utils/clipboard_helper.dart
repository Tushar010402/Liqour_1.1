import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_logger.dart';
import 'snackbar_helper.dart';
import 'haptic_feedback_helper.dart';

/// Clipboard Helper - Best Practice Clipboard Operations
/// Centralized clipboard management with user feedback

class ClipboardHelper {
  // Private constructor to prevent instantiation
  ClipboardHelper._();

  // ==================== Copy Operations ====================

  /// Copy text to clipboard
  static Future<bool> copyText(
    String text, {
    BuildContext? context,
    String? successMessage,
    bool showFeedback = true,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));

      AppLogger.info('Copied to clipboard: ${text.length} characters');

      if (showFeedback) {
        await HapticFeedbackHelper.light();

        if (context != null) {
          SnackbarHelper.copied(
            context: context,
            message: successMessage ?? 'Copied to clipboard',
          );
        }
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Copy to Clipboard',
        additionalData: {'textLength': text.length},
      );

      if (context != null) {
        SnackbarHelper.error(
          context: context,
          message: 'Failed to copy',
        );
      }

      return false;
    }
  }

  /// Copy with custom success message
  static Future<bool> copy(
    String text,
    BuildContext context, {
    required String message,
  }) async {
    return await copyText(
      text,
      context: context,
      successMessage: message,
    );
  }

  // ==================== Paste Operations ====================

  /// Paste text from clipboard
  static Future<String?> pasteText({
    BuildContext? context,
  }) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);

      if (data?.text != null) {
        AppLogger.info('Pasted from clipboard: ${data!.text!.length} characters');
        return data.text;
      } else {
        AppLogger.warning('Clipboard is empty');

        if (context != null) {
          SnackbarHelper.info(
            context: context,
            message: 'Clipboard is empty',
          );
        }

        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Paste from Clipboard',
      );

      if (context != null) {
        SnackbarHelper.error(
          context: context,
          message: 'Failed to paste',
        );
      }

      return null;
    }
  }

  /// Check if clipboard has text
  static Future<bool> hasText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text != null && data!.text!.isNotEmpty;
    } catch (e) {
      AppLogger.warning('Failed to check clipboard: $e');
      return false;
    }
  }

  // ==================== Predefined Copy Operations ====================

  /// Copy URL
  static Future<bool> copyUrl(
    String url,
    BuildContext context,
  ) async {
    return await copyText(
      url,
      context: context,
      successMessage: 'Link copied',
    );
  }

  /// Copy phone number
  static Future<bool> copyPhoneNumber(
    String phoneNumber,
    BuildContext context,
  ) async {
    return await copyText(
      phoneNumber,
      context: context,
      successMessage: 'Phone number copied',
    );
  }

  /// Copy email
  static Future<bool> copyEmail(
    String email,
    BuildContext context,
  ) async {
    return await copyText(
      email,
      context: context,
      successMessage: 'Email copied',
    );
  }

  /// Copy address
  static Future<bool> copyAddress(
    String address,
    BuildContext context,
  ) async {
    return await copyText(
      address,
      context: context,
      successMessage: 'Address copied',
    );
  }

  /// Copy order number
  static Future<bool> copyOrderNumber(
    String orderNumber,
    BuildContext context,
  ) async {
    return await copyText(
      orderNumber,
      context: context,
      successMessage: 'Order number copied',
    );
  }

  /// Copy tracking number
  static Future<bool> copyTrackingNumber(
    String trackingNumber,
    BuildContext context,
  ) async {
    return await copyText(
      trackingNumber,
      context: context,
      successMessage: 'Tracking number copied',
    );
  }

  /// Copy code (referral, promo, etc.)
  static Future<bool> copyCode(
    String code,
    BuildContext context, {
    String? codeType,
  }) async {
    return await copyText(
      code,
      context: context,
      successMessage: '${codeType ?? 'Code'} copied',
    );
  }

  /// Copy transaction ID
  static Future<bool> copyTransactionId(
    String transactionId,
    BuildContext context,
  ) async {
    return await copyText(
      transactionId,
      context: context,
      successMessage: 'Transaction ID copied',
    );
  }

  // ==================== Copy with Formatting ====================

  /// Copy as JSON (formatted)
  static Future<bool> copyAsJson(
    Map<String, dynamic> data,
    BuildContext context,
  ) async {
    try {
      final jsonString = _prettyJson(data);

      return await copyText(
        jsonString,
        context: context,
        successMessage: 'JSON copied',
      );
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Copy as JSON',
      );

      SnackbarHelper.error(
        context: context,
        message: 'Failed to copy JSON',
      );

      return false;
    }
  }

  /// Copy list as comma-separated values
  static Future<bool> copyAsCsv(
    List<String> items,
    BuildContext context, {
    String separator = ', ',
  }) async {
    final csvString = items.join(separator);

    return await copyText(
      csvString,
      context: context,
      successMessage: 'List copied',
    );
  }

  /// Copy with prefix and suffix
  static Future<bool> copyWithFormat(
    String text,
    BuildContext context, {
    String? prefix,
    String? suffix,
    String? successMessage,
  }) async {
    final formattedText = '${prefix ?? ''}$text${suffix ?? ''}';

    return await copyText(
      formattedText,
      context: context,
      successMessage: successMessage ?? 'Copied',
    );
  }

  // ==================== Utility Methods ====================

  /// Pretty print JSON
  static String _prettyJson(Map<String, dynamic> json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  /// Get clipboard text length
  static Future<int?> getTextLength() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text?.length;
    } catch (e) {
      return null;
    }
  }

  /// Clear clipboard
  static Future<bool> clear() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
      AppLogger.info('Clipboard cleared');
      return true;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Clear Clipboard',
      );
      return false;
    }
  }
}

/// JSON Encoder for pretty printing
class JsonEncoder {
  final String indent;

  const JsonEncoder.withIndent(this.indent);

  String convert(Map<String, dynamic> object) {
    return _encode(object, 0);
  }

  String _encode(dynamic object, int level) {
    if (object == null) return 'null';

    if (object is Map) {
      final entries = object.entries.map((e) {
        final key = '"${e.key}"';
        final value = _encode(e.value, level + 1);
        return '${indent * (level + 1)}$key: $value';
      }).join(',\n');

      return '{\n$entries\n${indent * level}}';
    }

    if (object is List) {
      final items = object.map((e) {
        return '${indent * (level + 1)}${_encode(e, level + 1)}';
      }).join(',\n');

      return '[\n$items\n${indent * level}]';
    }

    if (object is String) {
      return '"$object"';
    }

    return object.toString();
  }
}

/// Copyable Text Widget - Text with tap-to-copy functionality
class CopyableText extends StatelessWidget {
  final String text;
  final String? displayText;
  final TextStyle? style;
  final String? copyMessage;
  final bool showCopyIcon;
  final IconData copyIcon;
  final Color? copyIconColor;

  const CopyableText({
    super.key,
    required this.text,
    this.displayText,
    this.style,
    this.copyMessage,
    this.showCopyIcon = true,
    this.copyIcon = Icons.content_copy,
    this.copyIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ClipboardHelper.copyText(
          text,
          context: context,
          successMessage: copyMessage,
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayText ?? text,
              style: style,
            ),
            if (showCopyIcon) ...[
              const SizedBox(width: 4),
              Icon(
                copyIcon,
                size: 16,
                color: copyIconColor ?? Colors.grey[600],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Copyable Card - Card with tap-to-copy functionality
class CopyableCard extends StatelessWidget {
  final String text;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? copyMessage;

  const CopyableCard({
    super.key,
    required this.text,
    this.title,
    this.subtitle,
    this.icon,
    this.copyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          ClipboardHelper.copyText(
            text,
            context: context,
            successMessage: copyMessage,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 32),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.content_copy,
                size: 20,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
