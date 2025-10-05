import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'app_logger.dart';

/// File Helper - Best Practice File Operations
/// Centralized file management with error handling

class FileHelper {
  // Private constructor to prevent instantiation
  FileHelper._();

  // ==================== Directory Access ====================

  /// Get app documents directory
  static Future<Directory> getDocumentsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      AppLogger.info('Documents directory: ${directory.path}');
      return directory;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Documents Directory',
      );
      rethrow;
    }
  }

  /// Get app cache directory
  static Future<Directory> getCacheDirectory() async {
    try {
      final directory = await getTemporaryDirectory();
      AppLogger.info('Cache directory: ${directory.path}');
      return directory;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Cache Directory',
      );
      rethrow;
    }
  }

  /// Get app support directory
  static Future<Directory> getSupportDirectory() async {
    try {
      final directory = await getApplicationSupportDirectory();
      AppLogger.info('Support directory: ${directory.path}');
      return directory;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Support Directory',
      );
      rethrow;
    }
  }

  /// Get external storage directory (Android only)
  static Future<Directory?> getExternalStorageDirectory() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        AppLogger.info('External storage directory: ${directory.path}');
      } else {
        AppLogger.warning('External storage not available');
      }
      return directory;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get External Storage Directory',
      );
      return null;
    }
  }

  // ==================== File Operations ====================

  /// Write string to file
  static Future<File?> writeString({
    required String filename,
    required String content,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));

      await file.writeAsString(content);

      AppLogger.info('File written: ${file.path}');
      return file;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Write String to File',
        additionalData: {'filename': filename},
      );
      return null;
    }
  }

  /// Write bytes to file
  static Future<File?> writeBytes({
    required String filename,
    required Uint8List bytes,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));

      await file.writeAsBytes(bytes);

      AppLogger.info('File written: ${file.path} (${bytes.length} bytes)');
      return file;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Write Bytes to File',
        additionalData: {'filename': filename, 'size': bytes.length},
      );
      return null;
    }
  }

  /// Read string from file
  static Future<String?> readString({
    required String filename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));

      if (!await file.exists()) {
        AppLogger.warning('File does not exist: ${file.path}');
        return null;
      }

      final content = await file.readAsString();

      AppLogger.info('File read: ${file.path} (${content.length} characters)');
      return content;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Read String from File',
        additionalData: {'filename': filename},
      );
      return null;
    }
  }

  /// Read bytes from file
  static Future<Uint8List?> readBytes({
    required String filename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));

      if (!await file.exists()) {
        AppLogger.warning('File does not exist: ${file.path}');
        return null;
      }

      final bytes = await file.readAsBytes();

      AppLogger.info('File read: ${file.path} (${bytes.length} bytes)');
      return bytes;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Read Bytes from File',
        additionalData: {'filename': filename},
      );
      return null;
    }
  }

  /// Delete file
  static Future<bool> deleteFile({
    required String filename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));

      if (!await file.exists()) {
        AppLogger.warning('File does not exist: ${file.path}');
        return false;
      }

      await file.delete();

      AppLogger.info('File deleted: ${file.path}');
      return true;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Delete File',
        additionalData: {'filename': filename},
      );
      return false;
    }
  }

  /// Check if file exists
  static Future<bool> fileExists({
    required String filename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final file = File(path.join(directory.path, filename));
      final exists = await file.exists();

      AppLogger.debug('File exists check: ${file.path} = $exists');
      return exists;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'File Exists Check',
        additionalData: {'filename': filename},
      );
      return false;
    }
  }

  /// Copy file
  static Future<File?> copyFile({
    required File sourceFile,
    required String destinationFilename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final destinationPath = path.join(directory.path, destinationFilename);
      final copiedFile = await sourceFile.copy(destinationPath);

      AppLogger.info('File copied: ${sourceFile.path} -> ${copiedFile.path}');
      return copiedFile;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Copy File',
        additionalData: {'source': sourceFile.path, 'destination': destinationFilename},
      );
      return null;
    }
  }

  /// Move file
  static Future<File?> moveFile({
    required File sourceFile,
    required String destinationFilename,
    bool useCache = false,
  }) async {
    try {
      final directory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final destinationPath = path.join(directory.path, destinationFilename);
      final movedFile = await sourceFile.rename(destinationPath);

      AppLogger.info('File moved: ${sourceFile.path} -> ${movedFile.path}');
      return movedFile;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Move File',
        additionalData: {'source': sourceFile.path, 'destination': destinationFilename},
      );
      return null;
    }
  }

  // ==================== File Information ====================

  /// Get file size in bytes
  static Future<int?> getFileSize(File file) async {
    try {
      if (!await file.exists()) {
        AppLogger.warning('File does not exist: ${file.path}');
        return null;
      }

      final size = await file.length();
      AppLogger.debug('File size: ${file.path} = $size bytes');
      return size;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get File Size',
        additionalData: {'file': file.path},
      );
      return null;
    }
  }

  /// Get file size formatted
  static Future<String?> getFileSizeFormatted(File file) async {
    final size = await getFileSize(file);

    if (size == null) return null;

    return formatFileSize(size);
  }

  /// Format file size
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// Get file extension
  static String getFileExtension(String filename) {
    return path.extension(filename);
  }

  /// Get file name without extension
  static String getFileNameWithoutExtension(String filename) {
    return path.basenameWithoutExtension(filename);
  }

  /// Get file name from path
  static String getFileName(String filePath) {
    return path.basename(filePath);
  }

  /// Get file modification date
  static Future<DateTime?> getFileModificationDate(File file) async {
    try {
      if (!await file.exists()) {
        AppLogger.warning('File does not exist: ${file.path}');
        return null;
      }

      final stat = await file.stat();
      AppLogger.debug('File modified: ${file.path} = ${stat.modified}');
      return stat.modified;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get File Modification Date',
        additionalData: {'file': file.path},
      );
      return null;
    }
  }

  // ==================== Directory Operations ====================

  /// Create directory
  static Future<Directory?> createDirectory({
    required String directoryName,
    bool useCache = false,
  }) async {
    try {
      final parentDirectory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final directory = Directory(path.join(parentDirectory.path, directoryName));

      if (!await directory.exists()) {
        await directory.create(recursive: true);
        AppLogger.info('Directory created: ${directory.path}');
      } else {
        AppLogger.debug('Directory already exists: ${directory.path}');
      }

      return directory;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Create Directory',
        additionalData: {'directoryName': directoryName},
      );
      return null;
    }
  }

  /// Delete directory
  static Future<bool> deleteDirectory({
    required String directoryName,
    bool useCache = false,
    bool recursive = true,
  }) async {
    try {
      final parentDirectory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final directory = Directory(path.join(parentDirectory.path, directoryName));

      if (!await directory.exists()) {
        AppLogger.warning('Directory does not exist: ${directory.path}');
        return false;
      }

      await directory.delete(recursive: recursive);

      AppLogger.info('Directory deleted: ${directory.path}');
      return true;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Delete Directory',
        additionalData: {'directoryName': directoryName},
      );
      return false;
    }
  }

  /// List files in directory
  static Future<List<File>> listFiles({
    required String directoryName,
    bool useCache = false,
    String? extension,
  }) async {
    try {
      final parentDirectory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final directory = Directory(path.join(parentDirectory.path, directoryName));

      if (!await directory.exists()) {
        AppLogger.warning('Directory does not exist: ${directory.path}');
        return [];
      }

      final entities = await directory.list().toList();

      var files = entities
          .whereType<File>()
          .toList();

      if (extension != null) {
        files = files.where((file) => path.extension(file.path) == extension).toList();
      }

      AppLogger.info('Files in directory: ${directory.path} = ${files.length} files');
      return files;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'List Files',
        additionalData: {'directoryName': directoryName},
      );
      return [];
    }
  }

  /// Get directory size
  static Future<int> getDirectorySize({
    required String directoryName,
    bool useCache = false,
  }) async {
    try {
      final parentDirectory = useCache
          ? await getCacheDirectory()
          : await getDocumentsDirectory();

      final directory = Directory(path.join(parentDirectory.path, directoryName));

      if (!await directory.exists()) {
        AppLogger.warning('Directory does not exist: ${directory.path}');
        return 0;
      }

      int totalSize = 0;

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      AppLogger.info('Directory size: ${directory.path} = ${formatFileSize(totalSize)}');
      return totalSize;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Directory Size',
        additionalData: {'directoryName': directoryName},
      );
      return 0;
    }
  }

  // ==================== Cache Management ====================

  /// Clear cache directory
  static Future<bool> clearCache() async {
    try {
      final cacheDir = await getCacheDirectory();

      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create();
        AppLogger.info('Cache cleared');
        return true;
      }

      return false;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Clear Cache',
      );
      return false;
    }
  }

  /// Get cache size
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await getCacheDirectory();

      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      AppLogger.info('Cache size: ${formatFileSize(totalSize)}');
      return totalSize;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Get Cache Size',
      );
      return 0;
    }
  }

  /// Clear old cache files (older than specified days)
  static Future<int> clearOldCacheFiles({int olderThanDays = 7}) async {
    try {
      final cacheDir = await getCacheDirectory();

      if (!await cacheDir.exists()) {
        return 0;
      }

      final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
      int deletedCount = 0;

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      AppLogger.info('Cleared $deletedCount old cache files');
      return deletedCount;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Clear Old Cache Files',
      );
      return 0;
    }
  }

  // ==================== Utility Methods ====================

  /// Generate unique filename
  static String generateUniqueFilename({
    required String prefix,
    required String extension,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${prefix}_$timestamp$extension';
  }

  /// Sanitize filename
  static String sanitizeFilename(String filename) {
    // Remove invalid characters
    return filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}
