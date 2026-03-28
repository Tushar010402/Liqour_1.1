import 'package:json_annotation/json_annotation.dart';

// ══════════════════════════════════════════════════════════════════════════════
// JSON Converters for Null Safety
// ══════════════════════════════════════════════════════════════════════════════
//
// These converters handle null values from the backend gracefully,
// converting them to sensible defaults instead of causing parsing errors.
// ══════════════════════════════════════════════════════════════════════════════

/// Converts nullable double values from JSON
/// Handles: null, int, double, String representations
class NullableDoubleConverter implements JsonConverter<double, dynamic> {
  const NullableDoubleConverter();

  @override
  double fromJson(dynamic json) {
    if (json == null) return 0.0;
    if (json is int) return json.toDouble();
    if (json is double) return json;
    if (json is String) {
      if (json.isEmpty) return 0.0;
      return double.tryParse(json) ?? 0.0;
    }
    return 0.0;
  }

  @override
  dynamic toJson(double object) => object;
}

/// Converts nullable int values from JSON
/// Handles: null, int, double, String representations
class NullableIntConverter implements JsonConverter<int, dynamic> {
  const NullableIntConverter();

  @override
  int fromJson(dynamic json) {
    if (json == null) return 0;
    if (json is int) return json;
    if (json is double) return json.toInt();
    if (json is String) {
      if (json.isEmpty) return 0;
      return int.tryParse(json) ?? 0;
    }
    return 0;
  }

  @override
  dynamic toJson(int object) => object;
}

/// Converts nullable string values from JSON
/// Handles: null, empty strings, and other types
class NullableStringConverter implements JsonConverter<String, dynamic> {
  const NullableStringConverter();

  @override
  String fromJson(dynamic json) {
    if (json == null) return '';
    if (json is String) return json;
    return json.toString();
  }

  @override
  dynamic toJson(String object) => object;
}

/// Converts nullable bool values from JSON
/// Handles: null, bool, int (0/1), String ('true'/'false')
class NullableBoolConverter implements JsonConverter<bool, dynamic> {
  const NullableBoolConverter();

  @override
  bool fromJson(dynamic json) {
    if (json == null) return false;
    if (json is bool) return json;
    if (json is int) return json != 0;
    if (json is String) {
      if (json.isEmpty) return false;
      return json.toLowerCase() == 'true' || json == '1';
    }
    return false;
  }

  @override
  dynamic toJson(bool object) => object;
}

/// Converts nullable DateTime values from JSON
/// Handles: null, empty strings, ISO 8601 strings
/// IMPORTANT: Converts UTC timestamps to local time (IST in India) for display
class NullableDateTimeConverter implements JsonConverter<DateTime?, dynamic> {
  const NullableDateTimeConverter();

  @override
  DateTime? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is String) {
      if (json.isEmpty) return null;
      final parsed = DateTime.tryParse(json);
      // Convert UTC to local time (IST in India) for correct display
      return parsed?.toLocal();
    }
    if (json is DateTime) return json.toLocal();
    return null;
  }

  @override
  dynamic toJson(DateTime? object) {
    // Always send UTC back to backend
    return object?.toUtc().toIso8601String();
  }
}

/// Converts required DateTime values from JSON with fallback to now
/// Handles: null, empty strings, ISO 8601 strings
/// IMPORTANT: Converts UTC timestamps to local time (IST in India) for display
class RequiredDateTimeConverter implements JsonConverter<DateTime, dynamic> {
  const RequiredDateTimeConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is String) {
      if (json.isEmpty) return DateTime.now();
      final parsed = DateTime.tryParse(json);
      // Convert UTC to local time (IST in India) for correct display
      return parsed?.toLocal() ?? DateTime.now();
    }
    if (json is DateTime) return json.toLocal();
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) {
    // Always send UTC back to backend
    return object.toUtc().toIso8601String();
  }
}

/// Converts nullable List values from JSON
/// Handles: null -> empty list
class NullableListConverter<T> implements JsonConverter<List<T>, dynamic> {
  const NullableListConverter();

  @override
  List<T> fromJson(dynamic json) {
    if (json == null) return <T>[];
    if (json is List) return json.cast<T>();
    return <T>[];
  }

  @override
  dynamic toJson(List<T> object) => object;
}
