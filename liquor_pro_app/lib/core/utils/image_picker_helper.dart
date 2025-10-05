import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'app_logger.dart';
import 'permission_helper.dart';
import 'dialog_helper.dart';

/// Image Picker Helper - Best Practice Image Selection & Cropping
/// Centralized image picking with permission handling and cropping

class ImagePickerHelper {
  // Private constructor to prevent instantiation
  ImagePickerHelper._();

  static final ImagePicker _picker = ImagePicker();

  // ==================== Pick Image ====================

  /// Pick image from gallery
  static Future<File?> pickFromGallery(BuildContext context, {
    bool allowCropping = true,
    CropAspectRatio? aspectRatio,
    int? maxWidth,
    int? maxHeight,
    int imageQuality = 85,
  }) async {
    try {
      // Request permission
      final hasPermission = await PermissionHelper.requestPhotos(context);
      if (!hasPermission) {
        AppLogger.warning('Photo library permission denied');
        return null;
      }

      // Pick image
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
      );

      if (image == null) {
        AppLogger.debug('No image selected from gallery');
        return null;
      }

      AppLogger.info('Image picked from gallery: ${image.path}');

      // Crop if enabled
      if (allowCropping) {
        return await _cropImage(
          context: context,
          imagePath: image.path,
          aspectRatio: aspectRatio,
        );
      }

      return File(image.path);
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Pick from Gallery',
      );
      return null;
    }
  }

  /// Pick image from camera
  static Future<File?> pickFromCamera(BuildContext context, {
    bool allowCropping = true,
    CropAspectRatio? aspectRatio,
    int? maxWidth,
    int? maxHeight,
    int imageQuality = 85,
  }) async {
    try {
      // Request permission
      final hasPermission = await PermissionHelper.requestCamera(context);
      if (!hasPermission) {
        AppLogger.warning('Camera permission denied');
        return null;
      }

      // Pick image
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
      );

      if (image == null) {
        AppLogger.debug('No image captured from camera');
        return null;
      }

      AppLogger.info('Image captured from camera: ${image.path}');

      // Crop if enabled
      if (allowCropping) {
        return await _cropImage(
          context: context,
          imagePath: image.path,
          aspectRatio: aspectRatio,
        );
      }

      return File(image.path);
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Pick from Camera',
      );
      return null;
    }
  }

  /// Show picker options (Camera or Gallery)
  static Future<File?> showPicker(BuildContext context, {
    bool allowCropping = true,
    CropAspectRatio? aspectRatio,
    int? maxWidth,
    int? maxHeight,
    int imageQuality = 85,
  }) async {
    final source = await DialogHelper.choice<ImageSource>(
      context: context,
      title: 'Select Image Source',
      options: [ImageSource.camera, ImageSource.gallery],
      optionLabel: (source) => source == ImageSource.camera ? 'Camera' : 'Gallery',
      optionIcon: (source) => source == ImageSource.camera ? Icons.camera_alt : Icons.photo_library,
    );

    if (source == null) return null;

    if (source == ImageSource.camera) {
      return await pickFromCamera(
        context,
        allowCropping: allowCropping,
        aspectRatio: aspectRatio,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    } else {
      return await pickFromGallery(
        context,
        allowCropping: allowCropping,
        aspectRatio: aspectRatio,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    }
  }

  // ==================== Multiple Images ====================

  /// Pick multiple images from gallery
  static Future<List<File>> pickMultiple(BuildContext context, {
    int? maxImages,
    int? maxWidth,
    int? maxHeight,
    int imageQuality = 85,
  }) async {
    try {
      // Request permission
      final hasPermission = await PermissionHelper.requestPhotos(context);
      if (!hasPermission) {
        AppLogger.warning('Photo library permission denied');
        return [];
      }

      // Pick images
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
      );

      if (images.isEmpty) {
        AppLogger.debug('No images selected');
        return [];
      }

      // Limit number of images
      final selectedImages = maxImages != null && images.length > maxImages
          ? images.take(maxImages).toList()
          : images;

      AppLogger.info('${selectedImages.length} images selected');

      return selectedImages.map((xFile) => File(xFile.path)).toList();
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Pick Multiple Images',
      );
      return [];
    }
  }

  // ==================== Image Cropping ====================

  /// Crop image
  static Future<File?> _cropImage({
    required BuildContext context,
    required String imagePath,
    CropAspectRatio? aspectRatio,
  }) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        aspectRatio: aspectRatio,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Theme.of(context).primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: aspectRatio != null,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioLockEnabled: aspectRatio != null,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );

      if (croppedFile == null) {
        AppLogger.debug('Image cropping cancelled');
        return null;
      }

      AppLogger.info('Image cropped: ${croppedFile.path}');
      return File(croppedFile.path);
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Crop Image',
      );
      // Return original image if cropping fails
      return File(imagePath);
    }
  }

  /// Crop existing image
  static Future<File?> cropImage({
    required BuildContext context,
    required File imageFile,
    CropAspectRatio? aspectRatio,
  }) async {
    return await _cropImage(
      context: context,
      imagePath: imageFile.path,
      aspectRatio: aspectRatio,
    );
  }

  // ==================== Predefined Aspect Ratios ====================

  /// Square aspect ratio (1:1)
  static const CropAspectRatio squareRatio = CropAspectRatio(ratioX: 1, ratioY: 1);

  /// Profile picture aspect ratio (1:1)
  static const CropAspectRatio profileRatio = CropAspectRatio(ratioX: 1, ratioY: 1);

  /// Product image aspect ratio (4:3)
  static const CropAspectRatio productRatio = CropAspectRatio(ratioX: 4, ratioY: 3);

  /// Banner aspect ratio (16:9)
  static const CropAspectRatio bannerRatio = CropAspectRatio(ratioX: 16, ratioY: 9);

  /// Cover photo aspect ratio (16:9)
  static const CropAspectRatio coverRatio = CropAspectRatio(ratioX: 16, ratioY: 9);

  /// Story aspect ratio (9:16)
  static const CropAspectRatio storyRatio = CropAspectRatio(ratioX: 9, ratioY: 16);

  // ==================== Predefined Pickers ====================

  /// Pick profile picture (square, cropped)
  static Future<File?> pickProfilePicture(BuildContext context) async {
    return await showPicker(
      context,
      allowCropping: true,
      aspectRatio: profileRatio,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
  }

  /// Pick product image (4:3, cropped)
  static Future<File?> pickProductImage(BuildContext context) async {
    return await showPicker(
      context,
      allowCropping: true,
      aspectRatio: productRatio,
      maxWidth: 1024,
      maxHeight: 768,
      imageQuality: 85,
    );
  }

  /// Pick banner image (16:9, cropped)
  static Future<File?> pickBannerImage(BuildContext context) async {
    return await showPicker(
      context,
      allowCropping: true,
      aspectRatio: bannerRatio,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
  }

  /// Pick document/receipt (no crop, high quality)
  static Future<File?> pickDocument(BuildContext context) async {
    return await showPicker(
      context,
      allowCropping: false,
      imageQuality: 95,
    );
  }

  // ==================== Image Validation ====================

  /// Validate image file
  static Future<ImageValidationResult> validateImage({
    required File imageFile,
    int? maxSizeInBytes,
    int? minWidth,
    int? minHeight,
    int? maxWidth,
    int? maxHeight,
  }) async {
    try {
      // Check file exists
      if (!await imageFile.exists()) {
        return ImageValidationResult(
          isValid: false,
          error: 'File does not exist',
        );
      }

      // Check file size
      final fileSize = await imageFile.length();
      if (maxSizeInBytes != null && fileSize > maxSizeInBytes) {
        final maxSizeMB = (maxSizeInBytes / (1024 * 1024)).toStringAsFixed(2);
        return ImageValidationResult(
          isValid: false,
          error: 'Image size exceeds $maxSizeMB MB',
        );
      }

      // Check image dimensions (would need image package for this)
      // Skipping dimension check for now

      return ImageValidationResult(isValid: true);
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Validate Image',
      );
      return ImageValidationResult(
        isValid: false,
        error: 'Failed to validate image',
      );
    }
  }

  // ==================== Utility Methods ====================

  /// Get file size in MB
  static Future<double> getFileSizeInMB(File file) async {
    final bytes = await file.length();
    return bytes / (1024 * 1024);
  }

  /// Get file size formatted
  static Future<String> getFileSizeFormatted(File file) async {
    final bytes = await file.length();

    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
}

/// Image validation result
class ImageValidationResult {
  final bool isValid;
  final String? error;

  ImageValidationResult({
    required this.isValid,
    this.error,
  });
}
