import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth/models/device_session_models.dart';

/// Service to collect device information for session management
/// Provides device fingerprint data like Swiggy/Zomato for multi-device tracking
class DeviceInfoService {
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// Get device info for current device
  /// Returns DeviceInfo with device_id, name, OS, app version etc.
  static Future<DeviceInfo> getDeviceInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return DeviceInfo(
          deviceId: androidInfo.id,
          deviceName: _formatAndroidDeviceName(androidInfo),
          deviceType: 'mobile',
          osName: 'Android',
          osVersion: androidInfo.version.release,
          appVersion: packageInfo.version,
        );
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return DeviceInfo(
          deviceId: iosInfo.identifierForVendor ?? _generateFallbackId(),
          deviceName: iosInfo.name,
          deviceType: _getIOSDeviceType(iosInfo.model),
          osName: 'iOS',
          osVersion: iosInfo.systemVersion,
          appVersion: packageInfo.version,
        );
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfoPlugin.macOsInfo;
        return DeviceInfo(
          deviceId: macInfo.systemGUID ?? _generateFallbackId(),
          deviceName: macInfo.computerName,
          deviceType: 'desktop',
          osName: 'macOS',
          osVersion: macInfo.osRelease,
          appVersion: packageInfo.version,
        );
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        return DeviceInfo(
          deviceId: windowsInfo.deviceId,
          deviceName: windowsInfo.computerName,
          deviceType: 'desktop',
          osName: 'Windows',
          osVersion: windowsInfo.displayVersion,
          appVersion: packageInfo.version,
        );
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return DeviceInfo(
          deviceId: linuxInfo.machineId ?? _generateFallbackId(),
          deviceName: linuxInfo.prettyName,
          deviceType: 'desktop',
          osName: 'Linux',
          osVersion: linuxInfo.version ?? 'Unknown',
          appVersion: packageInfo.version,
        );
      }

      // Web or unknown platform
      return DeviceInfo(
        deviceId: _generateFallbackId(),
        deviceName: 'Web Browser',
        deviceType: 'web',
        osName: 'Web',
        osVersion: 'Unknown',
        appVersion: packageInfo.version,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error getting device info: $e');
      }
      // Return fallback info on error
      return DeviceInfo(
        deviceId: _generateFallbackId(),
        deviceName: 'Unknown Device',
        deviceType: 'mobile',
        osName: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
        appVersion: '1.0.0',
      );
    }
  }

  /// Format Android device name (Brand + Model)
  static String _formatAndroidDeviceName(AndroidDeviceInfo androidInfo) {
    final brand = androidInfo.brand;
    final model = androidInfo.model;

    // Capitalize brand name
    final capitalizedBrand = brand.isNotEmpty
        ? '${brand[0].toUpperCase()}${brand.substring(1)}'
        : 'Android';

    // Avoid duplicate brand name in model
    if (model.toLowerCase().startsWith(brand.toLowerCase())) {
      return model;
    }

    return '$capitalizedBrand $model';
  }

  /// Determine iOS device type from model string
  static String _getIOSDeviceType(String model) {
    final lowerModel = model.toLowerCase();
    if (lowerModel.contains('ipad')) {
      return 'tablet';
    } else if (lowerModel.contains('ipod')) {
      return 'ipod';
    }
    return 'mobile';
  }

  /// Generate a fallback device ID
  static String _generateFallbackId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get a user-friendly device description
  static Future<String> getDeviceDescription() async {
    final info = await getDeviceInfo();
    return '${info.deviceName} (${info.osName} ${info.osVersion})';
  }
}
