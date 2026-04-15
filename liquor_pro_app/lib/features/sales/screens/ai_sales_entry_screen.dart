import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../inventory/providers/product_provider.dart';
import '../../../core/constants/size_range_constants.dart';
import '../models/smart_sale_models.dart';
import '../services/smart_sale_service.dart';
import 'sales_summary_screen.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Phases the screen transitions through
enum _Phase { upload, processing, error, success }

class AISalesEntryScreen extends StatefulWidget {
  final String category; // 'English' or 'Beer'
  final String? size; // '750ML' etc.
  final DateTime selectedDate;

  const AISalesEntryScreen({
    super.key,
    required this.category,
    required this.selectedDate,
    this.size,
  });

  @override
  State<AISalesEntryScreen> createState() => _AISalesEntryScreenState();
}

class _AISalesEntryScreenState extends State<AISalesEntryScreen> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];
  _Phase _phase = _Phase.upload;

  // Processing state
  String _progressStatus = '';
  double _progressValue = 0.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Error state
  String _errorMessage = '';

  // Result
  SmartSaleResult? _result;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Image picking ──

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Add Receipt Image', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3855B3)),
              title: Text('Camera', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF3855B3)),
              title: Text('Gallery', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(imageQuality: 90);
        if (picked.isNotEmpty && mounted) {
          setState(() {
            for (final xf in picked) {
              if (_images.length < 5) _images.add(File(xf.path));
            }
          });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 90);
        if (picked != null && mounted) {
          setState(() {
            if (_images.length < 5) _images.add(File(picked.path));
          });
        }
      }
    } catch (e) {
      debugPrint('[AISalesEntry] Pick error: $e');
    }
  }

  void _removeImage(int index) {
    HapticFeedbackUtil.light();
    setState(() => _images.removeAt(index));
  }

  void _openImagePreview(int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewOverlay(
            images: _images,
            initialIndex: initialIndex,
            onDelete: (index) {
              Navigator.pop(context);
              _removeImage(index);
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  // ── Show "Proceed with AI" popup ──

  void _showProcessPopup() {
    HapticFeedbackUtil.medium();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                // AI Icon
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                Text('Process with AI', style: _heading(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                // Info pills
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _infoPill(Icons.image_outlined, '${_images.length} image${_images.length > 1 ? 's' : ''}'),
                    _infoPill(Icons.category_outlined, widget.category == 'Beer' ? 'Beer' : 'Whisky'),
                    if (widget.size != null) _infoPill(Icons.straighten, widget.size!),
                    _infoPill(Icons.calendar_today, DateFormat('dd MMM').format(widget.selectedDate)),
                  ],
                ),
                const SizedBox(height: 24),
                // Process button
                SizedBox(
                  width: double.infinity, height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(ctx); _startProcessing(); },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Process with AI', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFF888888))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD0D9F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF3855B3)),
          const SizedBox(width: 5),
          Text(text, style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF3855B3))),
        ],
      ),
    );
  }

  // ── Processing ──

  Future<void> _startProcessing() async {
    if (!mounted) return;
    final shopProvider = context.read<ShopSelectionProvider>();
    final shopId = shopProvider.selectedShopId;
    final shopName = shopProvider.selectedShopName ?? '';
    final authService = context.read<AuthService>();

    if (shopId == null) {
      if (mounted) SnackbarHelper.showError(context, 'No shop selected');
      return;
    }

    setState(() {
      _phase = _Phase.processing;
      _progressStatus = 'Preparing images...';
      _progressValue = 0.0;
      _cancelled = false;
    });

    // Keep screen awake during AI processing (prevents phone lock killing the request)
    try { await WakelockPlus.enable(); } catch (_) {}

    try {
      final service = SmartSaleService(authService);

      final apiCategory = widget.category == 'Beer' ? 'beer' : 'non_beer';

      final response = await service.processSmartSale(
        images: List<File>.from(_images),
        shopId: shopId,
        shopName: shopName,
        date: widget.selectedDate,
        category: apiCategory,
        size: widget.size,
        onProgress: (current, total, status) {
          if (!mounted || _cancelled) return;
          setState(() {
            _progressStatus = status;
            _progressValue = total > 0 ? current / total : 0;
          });
        },
      );

      // Release WakeLock after processing
      try { await WakelockPlus.disable(); } catch (_) {}

      if (_cancelled || !mounted) return;

      if (response.success && response.data != null) {
        _result = response.data!;
        _navigateToSummary();
      } else {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = response.message ?? 'Failed to process images';
        });
      }
    } catch (e) {
      try { await WakelockPlus.disable(); } catch (_) {}
      if (_cancelled || !mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _cancelProcessing() {
    _cancelled = true;
    try { WakelockPlus.disable(); } catch (_) {}
    setState(() => _phase = _Phase.upload);
  }

  // ── Navigate to Summary ──

  Future<void> _navigateToSummary() async {
    final result = _result;
    if (result == null) return;

    final items = <SalesSummaryItem>[];
    final skippedItems = <SkippedItem>[];

    for (final item in result.extractedItems) {
      if (item.productId == null || item.productId!.isEmpty) {
        skippedItems.add(SkippedItem(
          ocrName: item.brandName,
          quantity: item.quantity,
          rate: item.rate,
        ));
        continue;
      }
      final stock = item.dbStock ?? item.openingStock ?? item.availableStock ?? 0;
      // ocrText: original OCR text if different from resolved brand name (for alias learning)
      final rawOcr = item.ocrText;
      final ocrDiffers = rawOcr != null && rawOcr.isNotEmpty && rawOcr != item.brandName;
      items.add(SalesSummaryItem(
        productId: item.productId!,
        name: item.brandName,
        price: item.inventoryRate ?? item.rate,
        quantity: item.quantity,
        mrp: item.inventoryRate ?? item.rate,
        stock: stock,
        closingStock: stock - item.quantity,
        ocrText: ocrDiffers ? rawOcr : null,
        needsReview: item.needsReview,
        reviewReason: item.reviewReason,
        matchStatus: item.matchStatus,
        alternativeMatches: item.alternativeMatches,
      ));
    }

    if (items.isEmpty) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'No products could be matched from the receipt. Try a clearer image or switch to manual entry.';
      });
      return;
    }

    // Build available products — reload ALL products for this tenant, filter by category + size range
    final matchedIds = items.map((i) => i.productId).toSet();
    final availableProducts = <SalesSummaryItem>[];
    try {
      final productProvider = context.read<ProductProvider>();
      // Reload all products without size filter to get full catalog
      await productProvider.loadProducts(shopId: null, limit: 500, categoryId: null, size: null);
      final shopProvider = context.read<ShopSelectionProvider>();
      await productProvider.loadStock(shopId: shopProvider.selectedShopId);

      final allProducts = productProvider.products;
      final stockMap = productProvider.stockByProductId;
      final category = widget.category ?? '';

      for (final p in allProducts) {
        if (matchedIds.contains(p.id)) continue;
        // Filter by category
        final catName = (p.category?.name ?? '').toLowerCase();
        if (category == 'Beer' && !catName.contains('beer')) continue;
        if (category != 'Beer' && catName.contains('beer')) continue;
        // Filter by size range
        if (widget.size != null && widget.size!.isNotEmpty) {
          if (!SizeRangeConstants.sizeMatchesRange(p.size, widget.size!, category)) continue;
        }
        final stockEntry = stockMap[p.id];
        final stockQty = stockEntry?.quantity ?? p.stockQuantity ?? 0;
        availableProducts.add(SalesSummaryItem(
          productId: p.id,
          name: p.cleanName,
          price: p.mrp > 0 ? p.mrp : p.sellingPrice,
          quantity: 1,
          mrp: p.mrp > 0 ? p.mrp : p.sellingPrice,
          stock: stockQty,
          closingStock: stockQty,
        ));
      }
    } catch (_) {
      // ProductProvider not available — proceed without available products
    }

    final shopProvider = context.read<ShopSelectionProvider>();
    final authService = context.read<AuthService>();
    final apiCategory = widget.category == 'Beer' ? 'beer' : 'non_beer';

    Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SalesSummaryScreen(
          items: items,
          isAIMode: true,
          skippedItemCount: skippedItems.length,
          skippedItems: skippedItems,
          availableProducts: availableProducts,
          shopId: shopProvider.selectedShopId,
          saleDate: widget.selectedDate.toIso8601String().split('T')[0],
          saleCategory: apiCategory,
          saleSize: widget.size,
          authService: authService,
          processingTime: result.processingDetails != null
              ? result.processingDetails!.totalTimeMs / 1000.0
              : null,
          onSubmitItems: (finalItems) {
            // Pop summary, then pop this screen with 'submitted'
            Navigator.pop(context); // pop summary
            Navigator.pop(context, 'submitted'); // pop AI screen
          },
        ),
      ),
    ).then((val) {
      // If user backed out of summary, return to upload phase to retry
      if (mounted && _phase != _Phase.upload) {
        setState(() => _phase = _Phase.upload);
      }
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFE8EAF0)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
              child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: Text('AI Sales Entry', textAlign: TextAlign.center,
              style: _heading(size: 17, weight: FontWeight.w600)),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8EEF8),
              border: Border.all(color: const Color(0xFFD0D8E8), width: 1),
            ),
            child: Center(
              child: SizedBox(
                width: 20, height: 20,
                child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.upload:
        return _buildUploadPhase();
      case _Phase.processing:
        return _buildProcessingPhase();
      case _Phase.error:
        return _buildErrorPhase();
      case _Phase.success:
        return const SizedBox.shrink(); // navigated away
    }
  }

  // ── Phase 1: Upload ──

  Widget _buildUploadPhase() {
    return Column(
      children: [
        // Info bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF3855B3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.category == "Beer" ? "Beer" : "Whisky"}${widget.size != null ? " · ${widget.size}" : ""} · ${DateFormat("dd MMM yyyy").format(widget.selectedDate)}',
                    style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF3855B3)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Image thumbnails or empty state
        Expanded(
          child: _images.isEmpty ? _buildEmptyImageState() : _buildImageGrid(),
        ),

        // Bottom: Proceed button
        if (_images.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFE8EAF0)),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 18),
            child: SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  onPressed: _showProcessPopup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Proceed with AI', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyImageState() {
    return Center(
      child: GestureDetector(
        onTap: _showImageSourceSheet,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD0D9F0), width: 1.5),
              ),
              child: const Icon(Icons.add_a_photo_rounded, size: 36, color: Color(0xFF3855B3)),
            ),
            const SizedBox(height: 14),
            Text('Upload Receipt Images', style: _heading(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Take a photo or select from gallery', style: _body(size: 13, color: const Color(0xFF888888))),
            const SizedBox(height: 4),
            Text('Up to 5 images', style: _body(size: 12, color: const Color(0xFFAAAAAA))),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_images.length}/5 images attached', style: _body(size: 13, color: const Color(0xFF888888))),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85,
              ),
              itemCount: _images.length + (_images.length < 5 ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _images.length) {
                  // Add button
                  return GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD0D5DD), width: 1, style: BorderStyle.solid),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 28, color: Color(0xFF888888)),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }
                // Image thumbnail — tap to preview
                return GestureDetector(
                  onTap: () => _openImagePreview(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.expand(
                          child: Hero(
                            tag: 'receipt_image_$i',
                            child: Image.file(_images[i], fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      // Image index badge
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${i + 1}/${_images.length}',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(i),
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Phase 2: Processing ──

  Widget _buildProcessingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing AI icon
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF2962FF).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)],
                ),
                child: const Icon(Icons.auto_awesome, size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 28),
            Text('Processing...', style: _heading(size: 20, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _progressStatus,
                key: ValueKey(_progressStatus),
                style: _body(size: 14, color: const Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progressValue > 0 ? _progressValue : null,
                minHeight: 6,
                backgroundColor: const Color(0xFFE8EAF0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2962FF)),
              ),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: _cancelProcessing,
              child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFFD84315))),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 3: Error ──

  Widget _buildErrorPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.error_outline_rounded, size: 36, color: Color(0xFFD84315)),
            ),
            const SizedBox(height: 20),
            Text('Processing Failed', style: _heading(size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              style: _body(size: 13, color: const Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Retry
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _phase = _Phase.upload),
                icon: const Icon(Icons.refresh, size: 20),
                label: Text('Retry', style: _body(size: 15, weight: FontWeight.w700, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3855B3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Switch to manual
            SizedBox(
              width: double.infinity, height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'switch_manual'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Switch to Manual Entry', style: _body(size: 15, weight: FontWeight.w600, color: const Color(0xFF555555))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full-screen Image Preview with swipe ──

class _ImagePreviewOverlay extends StatefulWidget {
  final List<File> images;
  final int initialIndex;
  final void Function(int index) onDelete;

  const _ImagePreviewOverlay({
    required this.images,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_ImagePreviewOverlay> createState() => _ImagePreviewOverlayState();
}

class _ImagePreviewOverlayState extends State<_ImagePreviewOverlay> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable images
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Hero(
                    tag: 'receipt_image_$i',
                    child: Image.file(widget.images[i], fit: BoxFit.contain),
                  ),
                ),
              );
            },
          ),

          // Top bar: close + counter
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    // Close
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 22),
                      ),
                    ),
                    const Spacer(),
                    // Page indicator pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $total',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    // Delete
                    GestureDetector(
                      onTap: () => widget.onDelete(_currentIndex),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD84315).withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom dot indicators
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (i) {
                    final isActive = i == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
