/// Semantic version with proper comparison (not string compare)
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemanticVersion(this.major, this.minor, this.patch);

  /// Parse version string like "1.2.3" into SemanticVersion
  /// Returns (0,0,0) for malformed strings
  factory SemanticVersion.parse(String version) {
    try {
      // Strip leading 'v' if present
      final cleaned = version.startsWith('v') ? version.substring(1) : version;
      final parts = cleaned.split('.');
      if (parts.isEmpty || parts.length > 3) return const SemanticVersion(0, 0, 0);

      final major = int.tryParse(parts[0]) ?? 0;
      final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

      return SemanticVersion(major, minor, patch);
    } catch (_) {
      return const SemanticVersion(0, 0, 0);
    }
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticVersion &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Response model from GET /api/app/version-check
class AppVersionConfig {
  final String minVersion;
  final String latestVersion;
  final bool forceUpdate;
  final bool updateAvailable;
  final bool maintenanceMode;
  final String? releaseNotes;
  final String? maintenanceMessage;
  final String storeUrl;

  const AppVersionConfig({
    required this.minVersion,
    required this.latestVersion,
    required this.forceUpdate,
    required this.updateAvailable,
    required this.maintenanceMode,
    this.releaseNotes,
    this.maintenanceMessage,
    required this.storeUrl,
  });

  factory AppVersionConfig.fromJson(Map<String, dynamic> json) {
    return AppVersionConfig(
      minVersion: json['min_version'] as String? ?? '0.0.0',
      latestVersion: json['latest_version'] as String? ?? '0.0.0',
      forceUpdate: json['force_update'] as bool? ?? false,
      updateAvailable: json['update_available'] as bool? ?? false,
      maintenanceMode: json['maintenance_mode'] as bool? ?? false,
      releaseNotes: json['release_notes'] as String?,
      maintenanceMessage: json['maintenance_message'] as String?,
      storeUrl: json['store_url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'min_version': minVersion,
        'latest_version': latestVersion,
        'force_update': forceUpdate,
        'update_available': updateAvailable,
        'maintenance_mode': maintenanceMode,
        'release_notes': releaseNotes,
        'maintenance_message': maintenanceMessage,
        'store_url': storeUrl,
      };
}

/// Result of a version check operation
enum VersionCheckResult {
  upToDate,
  softUpdateAvailable,
  forceUpdateRequired,
  maintenanceMode,
  checkFailed,
}
