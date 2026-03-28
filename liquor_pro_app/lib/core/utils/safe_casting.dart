/// Safe Type Casting Utilities
/// Prevents runtime crashes from unsafe type casts
/// Provides null-safe alternatives for all common type conversions
library;

class SafeCast {
  /// Safe cast to num with default value
  static num toNum(dynamic value, {num defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safe cast to int with default value
  static int toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safe cast to double with default value
  static double toDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safe cast to String with default value
  static String toStringValue(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toString();
  }

  /// Safe cast to bool with default value
  static bool toBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return defaultValue;
  }

  /// Safe cast to List with default value
  static List<T> toList<T>(dynamic value, {List<T>? defaultValue}) {
    if (value == null) return defaultValue ?? [];
    if (value is List<T>) return value;
    if (value is List) {
      try {
        return value.cast<T>();
      } catch (_) {
        return defaultValue ?? [];
      }
    }
    return defaultValue ?? [];
  }

  /// Safe cast to Map with default value
  static Map<K, V> toMap<K, V>(dynamic value, {Map<K, V>? defaultValue}) {
    if (value == null) return defaultValue ?? {};
    if (value is Map<K, V>) return value;
    if (value is Map) {
      try {
        return value.cast<K, V>();
      } catch (_) {
        return defaultValue ?? {};
      }
    }
    return defaultValue ?? {};
  }

  /// Safe cast to DateTime with default value
  static DateTime? toDateTime(dynamic value, {DateTime? defaultValue}) {
    if (value == null) return defaultValue;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return defaultValue;
      }
    }
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (_) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  /// Nullable safe cast to num
  static num? toNumOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  /// Nullable safe cast to int
  static int? toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Nullable safe cast to double
  static double? toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Nullable safe cast to String
  static String? toStringOrNull(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
}

/// Extension methods for safe casting
extension SafeCastExtension on dynamic {
  /// Convert to int safely
  int asInt({int defaultValue = 0}) => SafeCast.toInt(this, defaultValue: defaultValue);

  /// Convert to double safely
  double asDouble({double defaultValue = 0.0}) => SafeCast.toDouble(this, defaultValue: defaultValue);

  /// Convert to num safely
  num asNum({num defaultValue = 0}) => SafeCast.toNum(this, defaultValue: defaultValue);

  /// Convert to String safely
  String asString({String defaultValue = ''}) => SafeCast.toStringValue(this, defaultValue: defaultValue);

  /// Convert to bool safely
  bool asBool({bool defaultValue = false}) => SafeCast.toBool(this, defaultValue: defaultValue);

  /// Convert to List safely
  List<T> asList<T>({List<T>? defaultValue}) => SafeCast.toList<T>(this, defaultValue: defaultValue);

  /// Convert to Map safely
  Map<K, V> asMap<K, V>({Map<K, V>? defaultValue}) => SafeCast.toMap<K, V>(this, defaultValue: defaultValue);

  /// Convert to DateTime safely
  DateTime? asDateTime({DateTime? defaultValue}) => SafeCast.toDateTime(this, defaultValue: defaultValue);

  /// Nullable conversions
  int? get asIntOrNull => SafeCast.toIntOrNull(this);
  double? get asDoubleOrNull => SafeCast.toDoubleOrNull(this);
  num? get asNumOrNull => SafeCast.toNumOrNull(this);
  String? get asStringOrNull => SafeCast.toStringOrNull(this);
}
