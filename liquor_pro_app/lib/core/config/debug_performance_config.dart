import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Debug & Simulator Performance Configuration
///
/// Centralizes all debug/simulator-aware interval tuning so that
/// background services don't saturate the CPU on the iOS Simulator
/// during development.
///
/// In release mode every getter returns the production value unchanged.
class DebugPerformanceConfig {
  DebugPerformanceConfig._();

  /// True when running on the iOS Simulator (not a physical device).
  /// Always false in release builds — the check is compiled out.
  static final bool isSimulator = kDebugMode && !_isPhysicalDevice();

  static bool _isPhysicalDevice() {
    // In release mode this is never called (short-circuited by kDebugMode).
    // On a real device the environment variable SIMULATOR_DEVICE_NAME is absent.
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return Platform.environment['SIMULATOR_DEVICE_NAME'] == null;
      }
      if (Platform.isAndroid) {
        // Android emulator sets 'ro.hardware' to 'goldfish' or 'ranchu',
        // but we can't read system props easily. Treat debug Android as
        // "simulator-like" for timer relaxation — no harm done.
        return true;
      }
    } catch (_) {}
    return true;
  }

  // ─── Timer intervals ────────────────────────────────────────────

  /// Connectivity polling interval.
  /// Production: 30 s → Debug: 120 s (DNS lookups are expensive in simulator).
  static Duration get connectivityCheckInterval =>
      kDebugMode ? const Duration(seconds: 120) : const Duration(seconds: 30);

  /// WebSocket keep-alive ping.
  /// Production: 30 s → Debug: 60 s.
  static Duration get websocketPingInterval =>
      kDebugMode ? const Duration(seconds: 60) : const Duration(seconds: 30);

  /// WebSocket token refresh check.
  /// Production: 30 s → Debug: 120 s.
  static Duration get websocketTokenCheckInterval =>
      kDebugMode ? const Duration(seconds: 120) : const Duration(seconds: 30);

  /// Request deduplication cache cleanup.
  /// Production: 30 s → Debug: 120 s.
  static Duration get deduplicationCleanupInterval =>
      kDebugMode ? const Duration(seconds: 120) : const Duration(seconds: 30);

  /// Offline queue processing tick.
  /// Production: 10 s → Debug: 60 s.
  static Duration get offlineQueueProcessInterval =>
      kDebugMode ? const Duration(seconds: 60) : const Duration(seconds: 10);

  /// Draft background sync.
  /// Production: 30 s → Debug: 120 s.
  static Duration get draftSyncInterval =>
      kDebugMode ? const Duration(seconds: 120) : const Duration(seconds: 30);

  /// Cache cleanup.
  /// Production: 5 min → Debug: 15 min.
  static Duration get cacheCleanupInterval =>
      kDebugMode ? const Duration(minutes: 15) : const Duration(minutes: 5);

  /// Log sync.
  /// Production: 5 min → Debug: 15 min.
  static Duration get logSyncInterval =>
      kDebugMode ? const Duration(minutes: 15) : const Duration(minutes: 5);

  // ─── Feature gates ──────────────────────────────────────────────

  /// Whether the FPS/Memory monitors should run.
  /// Disabled in debug — they add overhead and pollute the console.
  static bool get enablePerformanceMonitors => !kDebugMode;

  /// Whether Firebase Performance tracing should be active.
  /// Disabled in debug to reduce CPU and network overhead.
  static bool get enableFirebasePerformance => !kDebugMode;

  /// Whether Microsoft Clarity session replay should be active.
  /// Disabled in debug — adds significant overhead on simulator.
  static bool get enableClarity => !kDebugMode;

  /// Whether location services should be used on the simulator.
  /// Disabled because MapKit.SnapshotService consumes 100%+ CPU.
  static bool get enableLocationOnSimulator => false;

  /// Whether verbose debug prints should be emitted.
  /// Set to false to silence the 1 200+ print statements during normal dev.
  /// Flip to true only when actively debugging a specific issue.
  static const bool verboseDebugPrints = false;
}
