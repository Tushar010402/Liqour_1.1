import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../models/product.dart' as models;
import '../models/ai_purchase_models.dart';
import '../services/smart_purchase_service.dart';
import '../widgets/purchase_match_picker.dart';
import 'purchase_entry_screen.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

enum _Phase { upload, processing, review, error }

/// AI Purchase Entry Screen — smart extraction with review phase.
/// Upload invoice images → AI extraction → review matched/ambiguous/unmatched → purchase entry.
class AIPurchaseEntryScreen extends StatefulWidget {
  final String category; // 'English' or 'Beer'
  final DateTime selectedDate;
  final List<models.Product> allProducts;
  final Map<String, models.Stock> stockMap;

  const AIPurchaseEntryScreen({
    super.key,
    required this.category,
    required this.selectedDate,
    required this.allProducts,
    required this.stockMap,
  });

  @override
  State<AIPurchaseEntryScreen> createState() => _AIPurchaseEntryScreenState();
}

class _AIPurchaseEntryScreenState extends State<AIPurchaseEntryScreen> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];       // Bill/Invoice images
  final List<File> _gatePassImages = []; // Gate Pass images (optional)
  _Phase _phase = _Phase.upload;

  // Processing state
  String _progressStatus = '';
  double _progressValue = 0.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Error state
  String _errorMessage = '';

  // Result from backend
  SmartPurchaseResult? _result;
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

  // ── Helpers ──

  List<SmartPurchaseItem> get _matchedItems =>
      _result?.items.where((i) => i.isMatched).toList() ?? [];

  List<SmartPurchaseItem> get _reviewItems =>
      _result?.items.where((i) => i.needsReview).toList() ?? [];

  List<SmartPurchaseItem> get _notFoundItems =>
      _result?.items.where((i) => i.isNotFound).toList() ?? [];

  bool get _canProceed {
    return _reviewItems.every((i) => i.isResolved);
  }

  int get _resolvedCount {
    final items = _result?.items ?? [];
    return items.where((i) {
      if (i.isMatched) return true;
      return i.isResolved;
    }).length;
  }

  // ── Image picking ──

  void _showImageSourceSheet({bool isGatePass = false}) {
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
            Text(isGatePass ? 'Add Gate Pass Image' : 'Add Invoice Image', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: isGatePass ? const Color(0xFF2E7D32) : const Color(0xFF3855B3)),
              title: Text('Camera', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera, isGatePass: isGatePass); },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: isGatePass ? const Color(0xFF2E7D32) : const Color(0xFF3855B3)),
              title: Text('Gallery', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery, isGatePass: isGatePass); },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, {bool isGatePass = false}) async {
    try {
      final targetList = isGatePass ? _gatePassImages : _images;
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(imageQuality: 90);
        if (picked.isNotEmpty && mounted) {
          setState(() {
            for (final xf in picked) {
              if (targetList.length < 5) targetList.add(File(xf.path));
            }
          });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 90);
        if (picked != null && mounted) {
          setState(() {
            if (targetList.length < 5) targetList.add(File(picked.path));
          });
        }
      }
    } catch (e) {
      debugPrint('[AIPurchaseEntry] Pick error: $e');
    }
  }

  void _removeImage(int index) {
    HapticFeedbackUtil.light();
    setState(() => _images.removeAt(index));
  }

  void _showImagePreview(int initialIndex) {
    final pageController = PageController(initialPage: initialIndex);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, _, __) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Swipeable image pages
              PageView.builder(
                controller: pageController,
                itemCount: _images.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(_images[i], fit: BoxFit.contain),
                  ),
                ),
              ),
              // Top bar: close + page indicator
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16, right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: pageController,
                      builder: (_, __) {
                        final current = pageController.hasClients
                            ? (pageController.page?.round() ?? initialIndex) + 1
                            : initialIndex + 1;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Text('$current / ${_images.length}',
                            style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                        );
                      },
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
            ],
          ),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ── Process popup ──

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
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                Text('Process Invoice with AI', style: _heading(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _infoPill(Icons.image_outlined, '${_images.length} image${_images.length > 1 ? 's' : ''}'),
                    _infoPill(Icons.category_outlined, widget.category == 'Beer' ? 'Beer' : 'Whisky'),
                    _infoPill(Icons.calendar_today, DateFormat('dd MMM').format(widget.selectedDate)),
                    _infoPill(Icons.receipt_long_outlined, 'Purchase Invoice'),
                  ],
                ),
                const SizedBox(height: 24),
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
                          Text('Extract with AI', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
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

    // Keep screen awake during AI processing
    try { await WakelockPlus.enable(); } catch (_) {}

    try {
      final service = SmartPurchaseService(authService);

      final response = await service.extractFromInvoice(
        images: List<File>.from(_images),
        shopId: shopId,
        invoiceDate: widget.selectedDate,
        gatePassImages: _gatePassImages.isNotEmpty ? List<File>.from(_gatePassImages) : null,
        onProgress: (current, total, status) {
          if (!mounted || _cancelled) return;
          setState(() {
            _progressStatus = status;
            _progressValue = total > 0 ? current / total : 0;
          });
        },
      );

      // Release WakeLock
      try { await WakelockPlus.disable(); } catch (_) {}

      if (_cancelled || !mounted) return;

      if (response.success && response.data != null) {
        final result = response.data!;
        if (result.items.isEmpty) {
          setState(() {
            _phase = _Phase.error;
            _errorMessage = result.message.isNotEmpty
                ? result.message
                : 'No items could be extracted. Try a clearer image.';
          });
          return;
        }
        setState(() {
          _result = result;
          _phase = _Phase.review;
        });
      } else {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = response.message ?? 'Failed to process invoice';
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

  // ── Review actions ──

  Future<void> _resolveItem(SmartPurchaseItem item) async {
    final result = await PurchaseMatchPicker.show(context, item: item);
    if (result == null) return;

    setState(() {
      if (result == -1) {
        item.userSkipped = true;
        item.userSelectedIndex = -1;
      } else {
        item.userSelectedIndex = result;
        item.userSkipped = false;
      }
    });
  }

  void _skipItem(SmartPurchaseItem item) {
    setState(() {
      item.userSkipped = true;
      item.userSelectedIndex = -1;
    });
  }

  // ── Edit item inline ──

  void _showEditSheet(SmartPurchaseItem item) {
    final qtyController = TextEditingController(text: item.effectiveQuantity.toString());
    final costController = TextEditingController(
      text: item.effectiveCostPrice > 0 ? item.effectiveCostPrice.toStringAsFixed(2) : '',
    );
    final dutyController = TextEditingController(
      text: item.effectiveDutyFee > 0 ? item.effectiveDutyFee.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text('Edit Purchase Item', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 12),

            // Invoice brand info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8EAF0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 14, color: Color(0xFF666666)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${item.brandName} · ${item.size}',
                          style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF333333)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.resolvedBrandName != item.brandName) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _resolveItem(item);
                        if (mounted) _showEditSheet(item);
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_forward, size: 12, color: Color(0xFF3855B3)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Matched: ${item.resolvedBrandName}',
                              style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF3855B3)),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('Change \u25B8', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Editable fields
            Row(
              children: [
                Expanded(
                  child: _editField('Qty (bottles)', qtyController, isInt: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editField('Cost Price/btl', costController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editField('Duty/btl', dutyController),
                ),
              ],
            ),

            // DB reference
            if (item.dbCostPrice != null && item.dbCostPrice! > 0) ...[
              const SizedBox(height: 8),
              Text(
                'DB Cost: \u20B9${item.dbCostPrice!.toStringAsFixed(2)}',
                style: _body(size: 11, color: const Color(0xFF999999)),
              ),
            ],

            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFF666666))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        final qty = int.tryParse(qtyController.text);
                        final cost = double.tryParse(costController.text);
                        final duty = double.tryParse(dutyController.text);
                        if (qty != null && qty > 0) item.userQuantity = qty;
                        if (cost != null && cost > 0) item.userCostPrice = cost;
                        if (duty != null && duty >= 0) item.userDutyFee = duty;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: Text('Save Changes', style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(String label, TextEditingController controller, {bool isInt = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF888888))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          style: _body(size: 14, weight: FontWeight.w700),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2962FF), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── Navigate to PurchaseEntryScreen ──

  void _proceedToPurchaseEntry() {
    final items = _result?.items ?? [];
    final prefill = <String, int>{};
    final meta = <String, AIPurchaseItemMeta>{};

    for (final item in items) {
      final productId = item.resolvedProductId;
      if (productId == null || productId.isEmpty) continue;
      if (item.quantityBottles <= 0) continue;

      prefill[productId] = item.effectiveQuantity;

      final warnings = <String>[];
      if (item.hasRateMismatch) {
        warnings.add(
          'Invoice cost \u20B9${item.effectiveCostPrice.toStringAsFixed(0)} '
          'differs from DB \u20B9${item.dbCostPrice?.toStringAsFixed(0) ?? "?"}',
        );
      }
      if (item.needsReview) {
        warnings.add('Resolved from ${item.status == "low_confidence" ? "low confidence" : "ambiguous"} match');
      }
      for (final w in item.warnings) {
        warnings.add(w);
      }

      meta[productId] = AIPurchaseItemMeta(
        confidence: item.matchConfidence,
        aiRate: item.effectiveCostPrice,
        aiBrandName: item.brandName,
        aiSize: item.size,
        quantityBottles: item.effectiveQuantity,
        quantityUnit: item.quantityUnit,
        bottlesPerCase: item.bottlesPerCase,
        dutyFee: item.effectiveDutyFee,
        warnings: warnings,
      );
    }

    if (prefill.isEmpty) {
      SnackbarHelper.showError(context, 'No products resolved. Try manual entry.');
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseEntryScreen(
          category: widget.category,
          selectedDate: widget.selectedDate,
          allProducts: widget.allProducts,
          stockMap: widget.stockMap,
          prefillQuantities: prefill,
          isAIMode: true,
          aiItemMeta: meta,
        ),
      ),
    );
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
            child: Text('AI Purchase Entry', textAlign: TextAlign.center,
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
      case _Phase.review:
        return _buildReviewPhase();
      case _Phase.error:
        return _buildErrorPhase();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Phase 1: Upload
  // ═══════════════════════════════════════════════════════════

  Widget _buildUploadPhase() {
    return Column(
      children: [
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
                    '${widget.category == "Beer" ? "Beer" : "Whisky"} · Purchase · ${DateFormat("dd MMM yyyy").format(widget.selectedDate)}',
                    style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF3855B3)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── BILL / INVOICE SECTION ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF3855B3)),
              const SizedBox(width: 8),
              Text('Bill / Invoice', style: _heading(size: 14, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
              const Spacer(),
              Text('${_images.length}/5', style: _body(size: 12, color: const Color(0xFF888888))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: _images.isEmpty ? _buildEmptyImageState() : _buildImageGrid(),
        ),
        // ── GATE PASS SECTION (Optional) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.assignment_rounded, size: 18, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Text('Gate Pass', style: _heading(size: 14, weight: FontWeight.w700, color: const Color(0xFF2E7D32))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Optional', style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
              ),
              const Spacer(),
              if (_gatePassImages.isEmpty)
                GestureDetector(
                  onTap: () => _showImageSourceSheet(isGatePass: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF81C784)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 16, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text('Add', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                      ],
                    ),
                  ),
                )
              else
                Text('${_gatePassImages.length}/5', style: _body(size: 12, color: const Color(0xFF888888))),
            ],
          ),
        ),
        if (_gatePassImages.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              itemCount: _gatePassImages.length + (_gatePassImages.length < 5 ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _gatePassImages.length) {
                  return GestureDetector(
                    onTap: () => _showImageSourceSheet(isGatePass: true),
                    child: Container(
                      width: 64, height: 72, margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF81C784))),
                      child: const Icon(Icons.add_rounded, size: 22, color: Color(0xFF2E7D32)),
                    ),
                  );
                }
                return Stack(
                  children: [
                    Container(
                      width: 64, height: 72, margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_gatePassImages[i], fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 2, right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => _gatePassImages.removeAt(i)),
                        child: Container(
                          width: 20, height: 20,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 8),
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
                      Text(_gatePassImages.isNotEmpty ? 'Process Bill + Gate Pass' : 'Proceed with AI',
                        style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
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
            Text('Upload Invoice Images', style: _heading(size: 16, weight: FontWeight.w600)),
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
                  return GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD0D5DD), width: 1),
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
                return GestureDetector(
                  onTap: () => _showImagePreview(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.expand(child: Image.file(_images[i], fit: BoxFit.cover)),
                      ),
                      // Page number badge
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Text('${i + 1}', style: _body(size: 10, weight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(i),
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
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

  // ═══════════════════════════════════════════════════════════
  // Phase 2: Processing
  // ═══════════════════════════════════════════════════════════

  Widget _buildProcessingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Text('Processing Invoice...', style: _heading(size: 20, weight: FontWeight.w700)),
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

  // ═══════════════════════════════════════════════════════════
  // Phase 3: Review
  // ═══════════════════════════════════════════════════════════

  Widget _buildReviewPhase() {
    final result = _result!;
    final matched = _matchedItems;
    final review = _reviewItems;
    final notFound = _notFoundItems;

    return Column(
      children: [
        // Summary bar
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0D9F0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF3855B3)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${result.items.length} items extracted · $_resolvedCount resolved',
                      style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF3855B3)),
                    ),
                  ),
                ],
              ),
              // Vendor + invoice info
              if (result.matchedVendorName != null || result.invoiceNumber != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 24),
                    Expanded(
                      child: Text(
                        [
                          if (result.matchedVendorName != null) result.matchedVendorName!,
                          if (result.invoiceNumber != null) '#${result.invoiceNumber}',
                          if (result.invoiceDate != null) result.invoiceDate!,
                        ].join(' · '),
                        style: _body(size: 11, color: const Color(0xFF6B7280)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Scrollable sections
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              // Section A: Matched (green)
              if (matched.isNotEmpty) ...[
                _sectionHeader('Matched', matched.length, const Color(0xFF4CAF50), Icons.check_circle_outline),
                const SizedBox(height: 6),
                ...matched.map(_buildMatchedRow),
                const SizedBox(height: 16),
              ],

              // Section B: Needs Review (yellow)
              if (review.isNotEmpty) ...[
                _sectionHeader('Needs Review', review.length, const Color(0xFFFFA726), Icons.help_outline),
                const SizedBox(height: 6),
                ...review.map(_buildReviewRow),
                const SizedBox(height: 16),
              ],

              // Section C: Not Found (red)
              if (notFound.isNotEmpty) ...[
                _sectionHeader('Not Found', notFound.length, const Color(0xFFE53935), Icons.cancel_outlined),
                const SizedBox(height: 6),
                ...notFound.map(_buildNotFoundRow),
              ],

              // Total
              if (result.totalAmount > 0) ...[
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE8EAF0)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Invoice Total', style: _body(size: 14, weight: FontWeight.w700)),
                    Text('\u20B9${result.totalAmount.toStringAsFixed(0)}',
                      style: _heading(size: 16, weight: FontWeight.w800)),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Bottom bar
        const Divider(height: 1, color: Color(0xFFE8EAF0)),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _canProceed
                    ? const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)])
                    : const LinearGradient(colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: _canProceed ? _proceedToPurchaseEntry : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _canProceed ? 'Proceed to Purchase Entry' : 'Resolve all items to proceed',
                  style: _body(size: 15, weight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, int count, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text('$title ($count)', style: _heading(size: 14, weight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _buildMatchedRow(SmartPurchaseItem item) {
    final confPct = (item.matchConfidence * 100).toInt();
    final qtyLabel = item.quantityUnit == 'cases'
        ? '${item.quantityRaw}cs (${item.effectiveQuantity}btl)'
        : '${item.effectiveQuantity}btl';
    final nameMismatch = item.hasNameMismatch;
    final isEdited = item.userCostPrice != null || item.userDutyFee != null || item.userQuantity != null;

    return GestureDetector(
      onTap: () => _showEditSheet(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEdited ? const Color(0xFFF1F8E9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isEdited ? const Color(0xFFC8E6C9) : const Color(0xFFE0E0E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Invoice brand name + confidence
            Row(
              children: [
                _confidenceDot(item.matchConfidence),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.brandName,
                    style: _body(size: 13, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('$confPct%', style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF4CAF50))),
              ],
            ),

            // Row 2: Matched product name (if different)
            if (nameMismatch && item.matchedBrandName != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward, size: 11, color: Color(0xFFF57C00)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Matched: ${item.resolvedBrandName}',
                        style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFFF57C00)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Row 3: Size + Qty + pricing pills
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _sizePill(item.size),
                  _dataPill(qtyLabel),
                  _dataPill('Cost \u20B9${item.effectiveCostPrice.toStringAsFixed(0)}/btl'),
                  if (item.dbCostPrice != null && item.dbCostPrice! > 0)
                    _dataPill('DB \u20B9${item.dbCostPrice!.toStringAsFixed(0)}',
                      highlight: item.hasRateMismatch),
                  if (item.effectiveDutyFee > 0)
                    _dataPill('Duty \u20B9${item.effectiveDutyFee.toStringAsFixed(0)}',
                      color: const Color(0xFF7B1FA2)),
                ],
              ),
            ),

            // Row 4: Edit hint
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 5),
              child: Row(
                children: [
                  if (isEdited)
                    Text('Edited', style: _body(size: 10, weight: FontWeight.w700, color: const Color(0xFF4CAF50))),
                  const Spacer(),
                  Text('Edit \u25B8', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataPill(String text, {bool highlight = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: highlight ? const Color(0xFFFFCC80) : const Color(0xFFE0E0E0),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: _body(
          size: 10,
          weight: FontWeight.w600,
          color: color ?? (highlight ? const Color(0xFFF57C00) : const Color(0xFF666666)),
        ),
      ),
    );
  }

  Widget _buildReviewRow(SmartPurchaseItem item) {
    final isResolved = item.isResolved;
    final qtyLabel = item.quantityUnit == 'cases'
        ? '${item.quantityRaw}cs (${item.effectiveQuantity}btl)'
        : '${item.effectiveQuantity}btl';
    final confPct = (item.matchConfidence * 100).toInt();

    return GestureDetector(
      onTap: () => isResolved ? _showEditSheet(item) : _resolveItem(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isResolved ? const Color(0xFFF1F8E9) : const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isResolved ? const Color(0xFFC8E6C9) : const Color(0xFFFFE082)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Invoice brand name + confidence
            Row(
              children: [
                _confidenceDot(item.matchConfidence),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.brandName,
                    style: _body(size: 13, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('$confPct%', style: _body(size: 12, weight: FontWeight.w700,
                  color: isResolved ? const Color(0xFF4CAF50) : const Color(0xFFFFA726))),
              ],
            ),

            // Row 2: Resolved/status info
            if (isResolved && !item.userSkipped) ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Resolved: ${item.resolvedBrandName}',
                        style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF4CAF50)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (item.userSkipped) ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text('Skipped', style: _body(size: 11, color: const Color(0xFF999999))),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text('Tap to resolve', style: _body(size: 11, color: const Color(0xFFFFA726))),
              ),
            ],

            const SizedBox(height: 6),

            // Row 3: Size + Qty + pricing pills
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _sizePill(item.size),
                  _dataPill(qtyLabel),
                  if (item.effectiveCostPrice > 0)
                    _dataPill('Cost \u20B9${item.effectiveCostPrice.toStringAsFixed(0)}/btl'),
                  if (item.effectiveDutyFee > 0)
                    _dataPill('Duty \u20B9${item.effectiveDutyFee.toStringAsFixed(0)}',
                      color: const Color(0xFF7B1FA2)),
                ],
              ),
            ),

            // Row 4: Edit hint
            if (isResolved)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 5),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('Edit \u25B8', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundRow(SmartPurchaseItem item) {
    final qtyLabel = item.quantityUnit == 'cases'
        ? '${item.quantityRaw}cs (${item.quantityBottles}btl)'
        : '${item.quantityBottles}btl';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item.userSkipped ? const Color(0xFFF5F5F5) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.userSkipped ? const Color(0xFFE0E0E0) : const Color(0xFFFFCC80)),
      ),
      child: Row(
        children: [
          _confidenceDot(0.0),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brandName,
                  style: _body(size: 13, weight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _sizePill(item.size.isNotEmpty ? item.size : '?'),
                    const SizedBox(width: 8),
                    Text(qtyLabel, style: _body(size: 11, color: const Color(0xFF666666))),
                    const SizedBox(width: 8),
                    Text('No match', style: _body(size: 11, color: const Color(0xFFE53935))),
                  ],
                ),
              ],
            ),
          ),
          if (!item.userSkipped)
            TextButton(
              onPressed: () => _skipItem(item),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Skip', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
            )
          else
            Text('Skipped', style: _body(size: 11, color: const Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _confidenceDot(double confidence) {
    final Color color;
    if (confidence >= 0.8) {
      color = const Color(0xFF4CAF50);
    } else if (confidence >= 0.5) {
      color = const Color(0xFFFFA726);
    } else {
      color = const Color(0xFFE53935);
    }
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _sizePill(String size) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(size, style: _body(size: 10, weight: FontWeight.w700, color: const Color(0xFF1565C0))),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Phase 4: Error
  // ═══════════════════════════════════════════════════════════

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
