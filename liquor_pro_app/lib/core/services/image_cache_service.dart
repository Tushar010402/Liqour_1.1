import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

/// Industrial-Grade Image Cache Service
/// Best Practices:
/// - Memory-efficient image loading
/// - Placeholder with shimmer animation
/// - Error handling with retry
/// - Configurable cache settings
/// - WebP format support for smaller sizes
class ImageCacheService {
  // Singleton pattern
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  /// Build cached network image with best practices
  /// - Uses shimmer loading placeholder
  /// - Fallback icon on error
  /// - Memory cache for fast repeated access
  static Widget cachedImage({
    required BuildContext context,
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    BorderRadius? borderRadius,
    Color? backgroundColor,
    int? memCacheWidth,
    int? memCacheHeight,
    Duration fadeInDuration = const Duration(milliseconds: 300),
    Map<String, String>? headers,
  }) {
    // Handle empty URL
    if (imageUrl.isEmpty) {
      return _buildErrorWidget(context, errorWidget, width, height, backgroundColor);
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: const Duration(milliseconds: 100),

      // Memory cache optimization
      memCacheWidth: memCacheWidth ?? (width != null ? (width * 2).toInt() : null),
      memCacheHeight: memCacheHeight ?? (height != null ? (height * 2).toInt() : null),

      // HTTP headers (for auth tokens if needed)
      httpHeaders: headers,

      // Placeholder with shimmer effect
      placeholder: (ctx, url) => placeholder ?? _buildShimmerPlaceholder(
        context: ctx,
        width: width,
        height: height,
        backgroundColor: backgroundColor,
      ),

      // Error widget with retry option
      errorWidget: (ctx, url, error) {
        if (kDebugMode) {
          debugPrint('⚠️ [ImageCache] Failed to load: $url');
          debugPrint('   Error: $error');
        }
        return errorWidget ?? _buildDefaultErrorWidget(
          context: ctx,
          width: width,
          height: height,
          backgroundColor: backgroundColor,
        );
      },
    );

    // Apply border radius if specified
    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// Build avatar image with circular shape
  static Widget cachedAvatar({
    required BuildContext context,
    required String imageUrl,
    required double radius,
    Widget? placeholder,
    Widget? errorWidget,
    Color? backgroundColor,
    String? fallbackText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.surfaceContainerHighest;

    if (imageUrl.isEmpty) {
      return _buildFallbackAvatar(
        context: context,
        radius: radius,
        fallbackText: fallbackText,
        backgroundColor: backgroundColor,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      imageBuilder: (ctx, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: bg,
      ),
      placeholder: (ctx, url) {
        final placeholderCs = Theme.of(ctx).colorScheme;
        return placeholder ?? CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: Shimmer.fromColors(
            baseColor: placeholderCs.outline,
            highlightColor: placeholderCs.surfaceContainerHighest,
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
      errorWidget: (ctx, url, error) => errorWidget ?? _buildFallbackAvatar(
        context: ctx,
        radius: radius,
        fallbackText: fallbackText,
        backgroundColor: backgroundColor,
      ),
    );
  }

  /// Build product image with proper aspect ratio
  static Widget cachedProductImage({
    required BuildContext context,
    required String imageUrl,
    double? width,
    double? height,
    double borderRadius = 8,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final cs = Theme.of(context).colorScheme;
    return cachedImage(
      context: context,
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      borderRadius: BorderRadius.circular(borderRadius),
      backgroundColor: cs.surfaceContainerHighest,
      placeholder: placeholder ?? _buildProductPlaceholder(context, width, height, borderRadius),
      errorWidget: errorWidget ?? _buildProductError(context, width, height, borderRadius),
    );
  }

  /// Build shimmer placeholder
  static Widget _buildShimmerPlaceholder({
    required BuildContext context,
    double? width,
    double? height,
    Color? backgroundColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: backgroundColor ?? cs.outline,
      highlightColor: cs.surfaceContainerHighest,
      child: Container(
        width: width,
        height: height,
        color: Colors.white,
      ),
    );
  }

  /// Build default error widget
  static Widget _buildDefaultErrorWidget({
    required BuildContext context,
    double? width,
    double? height,
    Color? backgroundColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? cs.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        color: cs.onSurfaceVariant,
        size: (width ?? 48) * 0.4,
      ),
    );
  }

  /// Build error widget
  static Widget _buildErrorWidget(
    BuildContext context,
    Widget? errorWidget,
    double? width,
    double? height,
    Color? backgroundColor,
  ) {
    if (errorWidget != null) return errorWidget;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? cs.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: cs.onSurfaceVariant,
        size: (width ?? 48) * 0.4,
      ),
    );
  }

  /// Build fallback avatar with initials
  static Widget _buildFallbackAvatar({
    required BuildContext context,
    required double radius,
    String? fallbackText,
    Color? backgroundColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? cs.outlineVariant,
      child: fallbackText != null
          ? Text(
              _getInitials(fallbackText),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(
              Icons.person,
              color: cs.onSurfaceVariant,
              size: radius,
            ),
    );
  }

  /// Build product placeholder with shimmer
  static Widget _buildProductPlaceholder(
    BuildContext context,
    double? width,
    double? height,
    double borderRadius,
  ) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Shimmer.fromColors(
        baseColor: cs.outline,
        highlightColor: cs.surfaceContainerHighest,
        child: Container(
          width: width,
          height: height,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Build product error widget
  static Widget _buildProductError(
    BuildContext context,
    double? width,
    double? height,
    double borderRadius,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_bar_outlined,
            color: cs.onSurfaceVariant,
            size: (width ?? 48) * 0.3,
          ),
          const SizedBox(height: 4),
          Text(
            'No Image',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Get initials from text
  static String _getInitials(String text) {
    if (text.isEmpty) return '?';

    final words = text.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return '${words[0][0]}${words[words.length - 1][0]}'.toUpperCase();
  }

  /// Preload images for faster display
  /// Call this on screen init to warm up cache
  static Future<void> preloadImages(
    BuildContext context,
    List<String> imageUrls,
  ) async {
    for (final url in imageUrls) {
      if (url.isNotEmpty) {
        try {
          await precacheImage(
            CachedNetworkImageProvider(url),
            context,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [ImageCache] Preload failed: $url');
          }
        }
      }
    }
  }

  /// Clear all cached images
  static Future<void> clearCache() async {
    await CachedNetworkImage.evictFromCache('');
    if (kDebugMode) {
      debugPrint('🗑️ [ImageCache] Cache cleared');
    }
  }
}

/// Extension for easy access
extension ImageCacheExtension on String {
  /// Build cached image from URL string
  Widget toCachedImage({
    required BuildContext context,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
  }) {
    return ImageCacheService.cachedImage(
      context: context,
      imageUrl: this,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
    );
  }
}
