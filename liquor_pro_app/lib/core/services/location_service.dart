import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location Data Model for sales tracking
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy.toStringAsFixed(1),
  };

  @override
  String toString() => 'LocationData(lat: $latitude, lng: $longitude, accuracy: ${accuracy.toStringAsFixed(1)}m)';
}

/// Location Service for capturing GPS coordinates
/// Used for optional sales location tracking
///
/// IMPORTANT: Location is ALWAYS OPTIONAL - never blocks user workflow
class LocationService {
  /// Singleton instance
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Cached permission status
  LocationPermission? _cachedPermission;

  /// Get current location with graceful fallback
  /// Returns null if permission denied or unavailable - NEVER BLOCKS
  Future<LocationData?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          print('[LocationService] Location services disabled');
        }
        return null;
      }

      // Check permission
      var permission = _cachedPermission ?? await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print('[LocationService] Permission denied');
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print('[LocationService] Permission permanently denied');
        }
        return null;
      }

      // Cache the permission for future checks
      _cachedPermission = permission;

      // Get position with timeout (don't block user for too long)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Balance between accuracy and battery
        timeLimit: const Duration(seconds: 10),
      );

      if (kDebugMode) {
        print('[LocationService] Location captured: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
      }

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting location: $e');
      }
      return null;
    }
  }

  /// Check if location permission is granted (quick check, no request)
  Future<bool> hasLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      _cachedPermission = permission;
      return permission == LocationPermission.always ||
             permission == LocationPermission.whileInUse;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error checking permission: $e');
      }
      return false;
    }
  }

  /// Request location permission
  /// Returns true if granted, false otherwise
  Future<bool> requestPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      _cachedPermission = permission;
      return permission == LocationPermission.always ||
             permission == LocationPermission.whileInUse;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error requesting permission: $e');
      }
      return false;
    }
  }

  /// Check if location services are available on device
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      return false;
    }
  }

  /// Open location settings (when permanently denied)
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      return false;
    }
  }

  /// Open app settings (for permission management)
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      return false;
    }
  }
}
