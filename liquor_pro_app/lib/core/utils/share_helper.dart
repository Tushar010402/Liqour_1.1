import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'app_logger.dart';
import 'snackbar_helper.dart';

/// Share Helper - Best Practice Content Sharing
/// Centralized sharing functionality with error handling

class ShareHelper {
  // Private constructor to prevent instantiation
  ShareHelper._();

  // ==================== Text Sharing ====================

  /// Share text
  static Future<bool> shareText(
    String text, {
    String? subject,
    BuildContext? context,
  }) async {
    try {
      AppLogger.info('Sharing text: ${text.length} characters');

      final result = await Share.share(
        text,
        subject: subject,
      );

      _handleShareResult(result, context);
      return result.status == ShareResultStatus.success;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Share Text',
        additionalData: {'textLength': text.length},
      );

      _showError(context, 'Failed to share');
      return false;
    }
  }

  /// Share with custom subject
  static Future<bool> share(
    String text,
    String subject, {
    BuildContext? context,
  }) async {
    return await shareText(
      text,
      subject: subject,
      context: context,
    );
  }

  // ==================== File Sharing ====================

  /// Share single file
  static Future<bool> shareFile(
    File file, {
    String? text,
    String? subject,
    BuildContext? context,
  }) async {
    try {
      AppLogger.info('Sharing file: ${file.path}');

      final xFile = XFile(file.path);

      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: subject,
      );

      _handleShareResult(result, context);
      return result.status == ShareResultStatus.success;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Share File',
        additionalData: {'filePath': file.path},
      );

      _showError(context, 'Failed to share file');
      return false;
    }
  }

  /// Share multiple files
  static Future<bool> shareFiles(
    List<File> files, {
    String? text,
    String? subject,
    BuildContext? context,
  }) async {
    try {
      AppLogger.info('Sharing ${files.length} files');

      final xFiles = files.map((file) => XFile(file.path)).toList();

      final result = await Share.shareXFiles(
        xFiles,
        text: text,
        subject: subject,
      );

      _handleShareResult(result, context);
      return result.status == ShareResultStatus.success;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Share Files',
        additionalData: {'filesCount': files.length},
      );

      _showError(context, 'Failed to share files');
      return false;
    }
  }

  /// Share image file
  static Future<bool> shareImage(
    File imageFile, {
    String? text,
    BuildContext? context,
  }) async {
    return await shareFile(
      imageFile,
      text: text,
      context: context,
    );
  }

  /// Share multiple images
  static Future<bool> shareImages(
    List<File> imageFiles, {
    String? text,
    BuildContext? context,
  }) async {
    return await shareFiles(
      imageFiles,
      text: text,
      context: context,
    );
  }

  // ==================== Predefined Shares ====================

  /// Share app download link
  static Future<bool> shareApp({
    required String appName,
    required String appUrl,
    BuildContext? context,
  }) async {
    final text = 'Check out $appName!\n\nDownload here: $appUrl';

    return await shareText(
      text,
      subject: 'Check out $appName',
      context: context,
    );
  }

  /// Share product
  static Future<bool> shareProduct({
    required String productName,
    required String productUrl,
    String? imageUrl,
    double? price,
    BuildContext? context,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Check out this product:');
    buffer.writeln('📦 $productName');

    if (price != null) {
      buffer.writeln('💰 ₹${price.toStringAsFixed(2)}');
    }

    buffer.writeln('\n🔗 $productUrl');

    return await shareText(
      buffer.toString(),
      subject: 'Check out $productName',
      context: context,
    );
  }

  /// Share order details
  static Future<bool> shareOrder({
    required String orderNumber,
    required String orderDate,
    required double totalAmount,
    BuildContext? context,
  }) async {
    final text = '''
Order Details
━━━━━━━━━━━━━━━
Order #: $orderNumber
Date: $orderDate
Total: ₹${totalAmount.toStringAsFixed(2)}
━━━━━━━━━━━━━━━
''';

    return await shareText(
      text,
      subject: 'Order #$orderNumber',
      context: context,
    );
  }

  /// Share referral code
  static Future<bool> shareReferral({
    required String code,
    required String message,
    BuildContext? context,
  }) async {
    final text = '$message\n\nReferral Code: $code';

    return await shareText(
      text,
      subject: 'Referral Code',
      context: context,
    );
  }

  /// Share contact card
  static Future<bool> shareContact({
    required String name,
    String? phone,
    String? email,
    String? address,
    BuildContext? context,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Contact Details');
    buffer.writeln('━━━━━━━━━━━━━━━');
    buffer.writeln('Name: $name');

    if (phone != null) {
      buffer.writeln('Phone: $phone');
    }

    if (email != null) {
      buffer.writeln('Email: $email');
    }

    if (address != null) {
      buffer.writeln('Address: $address');
    }

    buffer.writeln('━━━━━━━━━━━━━━━');

    return await shareText(
      buffer.toString(),
      subject: 'Contact: $name',
      context: context,
    );
  }

  /// Share location
  static Future<bool> shareLocation({
    required double latitude,
    required double longitude,
    String? locationName,
    BuildContext? context,
  }) async {
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

    final text = locationName != null
        ? '$locationName\n\n📍 $mapsUrl'
        : '📍 Location: $mapsUrl';

    return await shareText(
      text,
      subject: locationName ?? 'Location',
      context: context,
    );
  }

  /// Share receipt/invoice
  static Future<bool> shareReceipt({
    required File receiptFile,
    required String receiptNumber,
    BuildContext? context,
  }) async {
    return await shareFile(
      receiptFile,
      text: 'Receipt #$receiptNumber',
      subject: 'Receipt #$receiptNumber',
      context: context,
    );
  }

  // ==================== Share with Options ====================

  /// Share with custom share sheet position (for iPad)
  static Future<bool> shareWithPosition({
    required String text,
    required BuildContext context,
    Rect? sharePositionOrigin,
    String? subject,
  }) async {
    try {
      AppLogger.info('Sharing with position');

      final result = await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin ?? _getSharePosition(context),
      );

      _handleShareResult(result, context);
      return result.status == ShareResultStatus.success;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Share with Position',
      );

      _showError(context, 'Failed to share');
      return false;
    }
  }

  // ==================== Utility Methods ====================

  /// Handle share result
  static void _handleShareResult(ShareResult result, BuildContext? context) {
    AppLogger.info('Share result: ${result.status}');

    if (result.status == ShareResultStatus.success) {
      AppLogger.info('Content shared successfully');
    } else if (result.status == ShareResultStatus.dismissed) {
      AppLogger.info('Share dismissed by user');
    } else if (result.status == ShareResultStatus.unavailable) {
      AppLogger.warning('Share unavailable');
      _showError(context, 'Sharing is not available');
    }
  }

  /// Get share position for iPad
  static Rect _getSharePosition(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? Size.zero;

    return Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );
  }

  /// Show error message
  static void _showError(BuildContext? context, String message) {
    if (context != null) {
      SnackbarHelper.error(
        context: context,
        message: message,
      );
    }
  }

  // ==================== Share via Specific Apps ====================

  /// Share via email (opens email client)
  static Future<bool> shareViaEmail({
    required String subject,
    required String body,
    List<String>? recipients,
    List<File>? attachments,
    BuildContext? context,
  }) async {
    try {
      final emailText = StringBuffer();
      emailText.writeln('Subject: $subject');
      emailText.writeln('');
      emailText.writeln(body);

      if (recipients != null && recipients.isNotEmpty) {
        emailText.writeln('');
        emailText.writeln('To: ${recipients.join(", ")}');
      }

      if (attachments != null && attachments.isNotEmpty) {
        return await shareFiles(
          attachments,
          text: emailText.toString(),
          subject: subject,
          context: context,
        );
      } else {
        return await shareText(
          emailText.toString(),
          subject: subject,
          context: context,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Share via Email',
      );

      _showError(context, 'Failed to share via email');
      return false;
    }
  }
}

/// Share Button Widget - Button with share functionality
class ShareButton extends StatelessWidget {
  final String text;
  final String? subject;
  final IconData icon;
  final String? label;
  final Color? color;
  final VoidCallback? onPressed;

  const ShareButton({
    super.key,
    required this.text,
    this.subject,
    this.icon = Icons.share,
    this.label,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      color: color,
      tooltip: label ?? 'Share',
      onPressed: () async {
        await ShareHelper.shareText(
          text,
          subject: subject,
          context: context,
        );
        onPressed?.call();
      },
    );
  }
}

/// Share Card Widget - Card with share functionality
class ShareCard extends StatelessWidget {
  final String text;
  final String? subject;
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;

  const ShareCard({
    super.key,
    required this.text,
    this.subject,
    required this.title,
    this.subtitle,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: leadingIcon != null ? Icon(leadingIcon, size: 32) : null,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.share),
        onTap: () async {
          await ShareHelper.shareText(
            text,
            subject: subject,
            context: context,
          );
        },
      ),
    );
  }
}
