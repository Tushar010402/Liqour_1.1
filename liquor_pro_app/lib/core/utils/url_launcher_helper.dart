import 'package:url_launcher/url_launcher.dart';
import 'app_logger.dart';
import 'package:flutter/material.dart';
import 'snackbar_helper.dart';

/// URL Launcher Helper - Best Practice External Link Handling
/// Centralized URL launching with error handling

class UrlLauncherHelper {
  // Private constructor to prevent instantiation
  UrlLauncherHelper._();

  // ==================== Web URLs ====================

  /// Open URL in browser
  static Future<bool> openUrl(
    String url, {
    BuildContext? context,
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    try {
      final uri = Uri.parse(url);

      AppLogger.info('Opening URL: $url');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: mode);

        if (launched) {
          AppLogger.info('URL opened successfully: $url');
          return true;
        } else {
          AppLogger.warning('Failed to open URL: $url');
          _showError(context, 'Could not open link');
          return false;
        }
      } else {
        AppLogger.warning('Cannot launch URL: $url');
        _showError(context, 'Invalid link');
        return false;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open URL',
        additionalData: {'url': url},
      );
      _showError(context, 'Failed to open link');
      return false;
    }
  }

  /// Open URL in web view (in-app)
  static Future<bool> openUrlInApp(
    String url, {
    BuildContext? context,
  }) async {
    return await openUrl(
      url,
      context: context,
      mode: LaunchMode.inAppWebView,
    );
  }

  /// Open URL in external browser
  static Future<bool> openUrlExternal(
    String url, {
    BuildContext? context,
  }) async {
    return await openUrl(
      url,
      context: context,
      mode: LaunchMode.externalApplication,
    );
  }

  // ==================== Phone & SMS ====================

  /// Make phone call
  static Future<bool> makePhoneCall(
    String phoneNumber, {
    BuildContext? context,
  }) async {
    try {
      // Remove non-numeric characters
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = Uri.parse('tel:$cleanNumber');

      AppLogger.info('Making phone call: $cleanNumber');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);

        if (launched) {
          AppLogger.info('Phone dialer opened: $cleanNumber');
          return true;
        } else {
          AppLogger.warning('Failed to open phone dialer');
          _showError(context, 'Could not make phone call');
          return false;
        }
      } else {
        AppLogger.warning('Cannot make phone call: $cleanNumber');
        _showError(context, 'Phone dialer not available');
        return false;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Make Phone Call',
        additionalData: {'phoneNumber': phoneNumber},
      );
      _showError(context, 'Failed to make phone call');
      return false;
    }
  }

  /// Send SMS
  static Future<bool> sendSms(
    String phoneNumber, {
    String? message,
    BuildContext? context,
  }) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = message != null
          ? Uri.parse('sms:$cleanNumber?body=${Uri.encodeComponent(message)}')
          : Uri.parse('sms:$cleanNumber');

      AppLogger.info('Sending SMS to: $cleanNumber');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);

        if (launched) {
          AppLogger.info('SMS app opened: $cleanNumber');
          return true;
        } else {
          AppLogger.warning('Failed to open SMS app');
          _showError(context, 'Could not send SMS');
          return false;
        }
      } else {
        AppLogger.warning('Cannot send SMS: $cleanNumber');
        _showError(context, 'SMS not available');
        return false;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Send SMS',
        additionalData: {'phoneNumber': phoneNumber},
      );
      _showError(context, 'Failed to send SMS');
      return false;
    }
  }

  // ==================== Email ====================

  /// Send email
  static Future<bool> sendEmail({
    required String to,
    String? subject,
    String? body,
    List<String>? cc,
    List<String>? bcc,
    BuildContext? context,
  }) async {
    try {
      final params = <String, String>{};

      if (subject != null) params['subject'] = subject;
      if (body != null) params['body'] = body;
      if (cc != null && cc.isNotEmpty) params['cc'] = cc.join(',');
      if (bcc != null && bcc.isNotEmpty) params['bcc'] = bcc.join(',');

      final uri = Uri(
        scheme: 'mailto',
        path: to,
        query: params.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&'),
      );

      AppLogger.info('Sending email to: $to');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);

        if (launched) {
          AppLogger.info('Email app opened: $to');
          return true;
        } else {
          AppLogger.warning('Failed to open email app');
          _showError(context, 'Could not send email');
          return false;
        }
      } else {
        AppLogger.warning('Cannot send email: $to');
        _showError(context, 'Email not available');
        return false;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Send Email',
        additionalData: {'to': to},
      );
      _showError(context, 'Failed to send email');
      return false;
    }
  }

  // ==================== Maps & Navigation ====================

  /// Open location in maps
  static Future<bool> openMaps({
    double? latitude,
    double? longitude,
    String? address,
    BuildContext? context,
  }) async {
    try {
      Uri uri;

      if (latitude != null && longitude != null) {
        // Open with coordinates
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
      } else if (address != null) {
        // Open with address
        final encodedAddress = Uri.encodeComponent(address);
        uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
      } else {
        AppLogger.warning('No location provided for maps');
        _showError(context, 'No location provided');
        return false;
      }

      AppLogger.info('Opening maps with location');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (launched) {
          AppLogger.info('Maps opened successfully');
          return true;
        } else {
          AppLogger.warning('Failed to open maps');
          _showError(context, 'Could not open maps');
          return false;
        }
      } else {
        AppLogger.warning('Cannot open maps');
        _showError(context, 'Maps not available');
        return false;
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open Maps',
        additionalData: {
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
        },
      );
      _showError(context, 'Failed to open maps');
      return false;
    }
  }

  /// Open navigation to location
  static Future<bool> openNavigation({
    required double latitude,
    required double longitude,
    BuildContext? context,
  }) async {
    try {
      // Use Google Maps navigation deep link
      final uri = Uri.parse('google.navigation:q=$latitude,$longitude');

      AppLogger.info('Opening navigation to: $latitude, $longitude');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (launched) {
          AppLogger.info('Navigation opened successfully');
          return true;
        }
      }

      // Fallback to regular maps
      return await openMaps(
        latitude: latitude,
        longitude: longitude,
        context: context,
      );
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open Navigation',
        additionalData: {'latitude': latitude, 'longitude': longitude},
      );
      _showError(context, 'Failed to open navigation');
      return false;
    }
  }

  // ==================== Social Media ====================

  /// Open WhatsApp chat
  static Future<bool> openWhatsApp(
    String phoneNumber, {
    String? message,
    BuildContext? context,
  }) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = message != null
          ? Uri.parse('https://wa.me/$cleanNumber?text=${Uri.encodeComponent(message)}')
          : Uri.parse('https://wa.me/$cleanNumber');

      AppLogger.info('Opening WhatsApp: $cleanNumber');

      return await openUrl(uri.toString(), context: context);
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open WhatsApp',
        additionalData: {'phoneNumber': phoneNumber},
      );
      _showError(context, 'Failed to open WhatsApp');
      return false;
    }
  }

  /// Open Facebook page
  static Future<bool> openFacebook(
    String pageId, {
    BuildContext? context,
  }) async {
    // Try app first, fallback to web
    final appUrl = 'fb://page/$pageId';
    final webUrl = 'https://www.facebook.com/$pageId';

    try {
      final appUri = Uri.parse(appUrl);
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri);
      }
    } catch (_) {}

    return await openUrl(webUrl, context: context);
  }

  /// Open Instagram profile
  static Future<bool> openInstagram(
    String username, {
    BuildContext? context,
  }) async {
    // Try app first, fallback to web
    final appUrl = 'instagram://user?username=$username';
    final webUrl = 'https://www.instagram.com/$username';

    try {
      final appUri = Uri.parse(appUrl);
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri);
      }
    } catch (_) {}

    return await openUrl(webUrl, context: context);
  }

  /// Open Twitter profile
  static Future<bool> openTwitter(
    String username, {
    BuildContext? context,
  }) async {
    // Try app first, fallback to web
    final appUrl = 'twitter://user?screen_name=$username';
    final webUrl = 'https://twitter.com/$username';

    try {
      final appUri = Uri.parse(appUrl);
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri);
      }
    } catch (_) {}

    return await openUrl(webUrl, context: context);
  }

  // ==================== App Store ====================

  /// Open app in store (iOS App Store or Google Play)
  static Future<bool> openAppStore({
    required String appId,
    BuildContext? context,
  }) async {
    try {
      // iOS App Store
      final iosUrl = 'https://apps.apple.com/app/id$appId';

      // Android Play Store
      final androidUrl = 'https://play.google.com/store/apps/details?id=$appId';

      // Detect platform and open appropriate store
      if (Theme.of(context ?? NavigationService.navigatorKey.currentContext!).platform ==
          TargetPlatform.iOS) {
        return await openUrl(iosUrl, context: context);
      } else {
        return await openUrl(androidUrl, context: context);
      }
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open App Store',
        additionalData: {'appId': appId},
      );
      _showError(context, 'Failed to open app store');
      return false;
    }
  }

  // ==================== Utility Methods ====================

  /// Check if URL can be launched
  static Future<bool> canLaunch(String url) async {
    try {
      final uri = Uri.parse(url);
      return await canLaunchUrl(uri);
    } catch (e) {
      AppLogger.warning('Cannot parse URL: $url');
      return false;
    }
  }

  /// Close in-app web view
  static Future<void> closeInAppWebView() async {
    try {
      await closeWebView();
      AppLogger.info('In-app web view closed');
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Close In-App Web View',
      );
    }
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
}

/// Navigation Service for global context access
class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get currentContext => navigatorKey.currentContext;
}
