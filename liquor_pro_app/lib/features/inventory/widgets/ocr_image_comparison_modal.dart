import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';

/// Image comparison modal for verifying OCR accuracy
///
/// FEATURES:
/// - Zoom & pan on invoice images
/// - Swipe between multiple images
/// - Side-by-side comparison (image vs data)
/// - Highlight selected item
/// - Modern iOS design
///
/// USAGE:
/// ```dart
/// showOCRImageComparison(
///   context: context,
///   imagePaths: ['path/to/image1.jpg', 'path/to/image2.jpg'],
///   items: ocrItems,
///   selectedItem: currentItem,
/// );
/// ```
class OCRImageComparisonModal extends StatefulWidget {
  final List<String> imagePaths;
  final List<DeduplicatedItem> items;
  final DeduplicatedItem? selectedItem;
  final int initialPage;

  const OCRImageComparisonModal({
    super.key,
    required this.imagePaths,
    required this.items,
    this.selectedItem,
    this.initialPage = 0,
  });

  @override
  State<OCRImageComparisonModal> createState() =>
      _OCRImageComparisonModalState();
}

class _OCRImageComparisonModalState extends State<OCRImageComparisonModal> {
  late PageController _pageController;
  late int _currentPage;
  bool _showData = true;
  DeduplicatedItem? _highlightedItem;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    _highlightedItem = widget.selectedItem;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Image Gallery with Zoom
          _buildImageGallery(),

          // Overlay with extracted data
          if (_showData) _buildDataOverlay(),

          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  /// Build app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Invoice ${_currentPage + 1} of ${widget.imagePaths.length}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      actions: [
        // Toggle data overlay
        IconButton(
          icon: Icon(
            _showData ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              _showData = !_showData;
            });
          },
          tooltip: _showData ? 'Hide data' : 'Show data',
        ),

        // Info button
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
          onPressed: _showHelpDialog,
          tooltip: 'Help',
        ),
      ],
    );
  }

  /// Build image gallery with zoom/pan
  Widget _buildImageGallery() {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (BuildContext context, int index) {
        final imagePath = widget.imagePaths[index];

        return PhotoViewGalleryPageOptions(
          imageProvider: FileImage(File(imagePath)),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4.0,
          heroAttributes: PhotoViewHeroAttributes(tag: 'invoice_$index'),
        );
      },
      itemCount: widget.imagePaths.length,
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(
          value: event == null
              ? 0
              : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
          color: Colors.white,
        ),
      ),
      backgroundDecoration: const BoxDecoration(
        color: Colors.black,
      ),
      pageController: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
    );
  }

  /// Build data overlay showing extracted items
  Widget _buildDataOverlay() {
    final itemsFromCurrentImage = widget.items.where((item) {
      // Filter items from current image
      // This would require session_id mapping to image index
      return true; // For now, show all items
    }).toList();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 100,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.list_alt_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Extracted Items',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${itemsFromCurrentImage.length} items',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: itemsFromCurrentImage.length,
                itemBuilder: (context, index) {
                  final item = itemsFromCurrentImage[index];
                  final isHighlighted = item.id == _highlightedItem?.id;

                  return _buildItemCard(item, isHighlighted);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual item card
  Widget _buildItemCard(DeduplicatedItem item, bool isHighlighted) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _highlightedItem = isHighlighted ? null : item;
        });
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHighlighted
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? Colors.white
                : Colors.white.withOpacity(0.2),
            width: isHighlighted ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand name
            Text(
              item.brandText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Size
            Text(
              item.sizeText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),

            // Stock & Price
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  '${item.totalStock}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const Spacer(),
                if (item.sellingPrice != null) ...[
                  Icon(
                    Icons.currency_rupee_rounded,
                    size: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  Text(
                    item.sellingPrice!.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ],
            ),

            const Spacer(),

            // Confidence badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _getConfidenceColor(item.matchConfidence),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(item.matchConfidence * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build bottom controls
  Widget _buildBottomControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous button
              if (widget.imagePaths.length > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                  color: _currentPage > 0
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  onPressed: _currentPage > 0
                      ? () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      : null,
                ),

              const SizedBox(width: 16),

              // Page indicators
              if (widget.imagePaths.length > 1)
                Row(
                  children: List.generate(
                    widget.imagePaths.length,
                    (index) => Container(
                      width: index == _currentPage ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == _currentPage
                            ? Colors.white
                            : Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 16),

              // Next button
              if (widget.imagePaths.length > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded),
                  color: _currentPage < widget.imagePaths.length - 1
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  onPressed: _currentPage < widget.imagePaths.length - 1
                      ? () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show help dialog
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, size: 24),
            SizedBox(width: 8),
            Text('How to Use'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpItem(
              icon: Icons.zoom_in_rounded,
              text: 'Pinch to zoom in/out',
            ),
            _HelpItem(
              icon: Icons.pan_tool_rounded,
              text: 'Drag to pan around',
            ),
            _HelpItem(
              icon: Icons.swipe_rounded,
              text: 'Swipe left/right to switch images',
            ),
            _HelpItem(
              icon: Icons.visibility_rounded,
              text: 'Tap eye icon to show/hide data',
            ),
            _HelpItem(
              icon: Icons.touch_app_rounded,
              text: 'Tap item card to highlight',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Get confidence color
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) {
      return AppColors.success;
    } else if (confidence >= 0.5) {
      return AppColors.warning;
    } else {
      return AppColors.error;
    }
  }
}

/// Help item widget
class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HelpItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show image comparison modal
void showOCRImageComparison({
  required BuildContext context,
  required List<String> imagePaths,
  required List<DeduplicatedItem> items,
  DeduplicatedItem? selectedItem,
  int initialPage = 0,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OCRImageComparisonModal(
        imagePaths: imagePaths,
        items: items,
        selectedItem: selectedItem,
        initialPage: initialPage,
      ),
    ),
  );
}
