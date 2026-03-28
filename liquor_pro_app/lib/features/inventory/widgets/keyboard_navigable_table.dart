import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import '../services/brand_intelligence_service.dart';

/// Excel-like Keyboard Navigable OCR Review Table
///
/// Features:
/// - Arrow key navigation (Up, Down, Left, Right)
/// - Tab/Shift+Tab for next/previous cell
/// - Enter to start editing, Escape to cancel
/// - F2 for direct edit mode
/// - Ctrl+A to select all
/// - Ctrl+S to save (triggers accept)
/// - Home/End for row start/end
/// - Page Up/Down for scrolling
/// - Visual focus indicators
/// - Automatic scroll to keep focused cell visible
class KeyboardNavigableTable extends StatefulWidget {
  final List<DeduplicatedItem> items;
  final Set<String> selectedItemIds;
  final Map<String, int> editedQuantities;
  final Map<String, String> editedBrandNames;
  final Map<String, double> editedPrices;
  final Map<String, bool> acceptanceStates;
  final Map<String, bool> rejectionStates;
  final ValueChanged<String> onItemSelected;
  final Function(String itemId, int quantity) onQuantityChanged;
  final Function(String itemId, String brandName) onBrandNameChanged;
  final Function(String itemId, double price) onPriceChanged;
  final VoidCallback? onSave;
  final VoidCallback? onSelectAll;

  const KeyboardNavigableTable({
    super.key,
    required this.items,
    required this.selectedItemIds,
    required this.editedQuantities,
    required this.editedBrandNames,
    required this.editedPrices,
    required this.acceptanceStates,
    required this.rejectionStates,
    required this.onItemSelected,
    required this.onQuantityChanged,
    required this.onBrandNameChanged,
    required this.onPriceChanged,
    this.onSave,
    this.onSelectAll,
  });

  @override
  State<KeyboardNavigableTable> createState() => _KeyboardNavigableTableState();
}

class _KeyboardNavigableTableState extends State<KeyboardNavigableTable> {
  // Focus management
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Cell position
  int _focusedRow = 0;
  int _focusedColumn = 0;

  // Edit mode
  bool _isEditing = false;
  TextEditingController? _editController;
  FocusNode? _editFocusNode;

  // Column definitions
  static const List<String> columns = [
    'select',    // 0
    'number',    // 1
    'quality',   // 2
    'brand',     // 3
    'size',      // 4
    'quantity',  // 5
    'price',     // 6
    'status',    // 7
  ];

  // Editable columns
  static const Set<int> editableColumns = {3, 5, 6}; // brand, quantity, price

  // Search and filter state (from enhanced table)
  String searchQuery = '';
  Timer? _searchDebouncer;
  bool showOnlyIssues = false;

  // Data quality scores cache
  final Map<String, DataQualityScore> _qualityScores = {};
  final Map<String, AutoFixResult> _autoFixes = {};

  @override
  void initState() {
    super.initState();
    _calculateQualityScores();
    _tableFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _tableFocusNode.dispose();
    _scrollController.dispose();
    _editController?.dispose();
    _editFocusNode?.dispose();
    _searchDebouncer?.cancel();
    super.dispose();
  }

  void _calculateQualityScores() {
    for (final item in widget.items) {
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      if (itemId.isNotEmpty) {
        final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
        final price = widget.editedPrices[itemId] ?? item.sellingPrice;
        final quantity = widget.editedQuantities[itemId] ?? item.totalStock;

        _qualityScores[itemId] = BrandIntelligenceService.calculateDataQuality(
          brandText: brandName,
          sizeText: item.sizeText,
          price: price,
          quantity: quantity,
        );
      }
    }
  }

  List<DeduplicatedItem> get filteredItems {
    var filtered = widget.items;

    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final brandName = widget.editedBrandNames[item.sourceItemIds.first] ?? item.brandText;
        final searchLower = searchQuery.toLowerCase();

        return brandName.toLowerCase().contains(searchLower) ||
               item.sizeText.toLowerCase().contains(searchLower) ||
               item.sellingPrice.toString().contains(searchLower) ||
               item.totalStock.toString().contains(searchLower);
      }).toList();
    }

    if (showOnlyIssues) {
      filtered = filtered.where((item) {
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
        final score = _qualityScores[itemId];
        return score != null && score.score < 0.8;
      }).toList();
    }

    return filtered;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    // Ctrl/Cmd combinations
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyA) {
        // Select All
        widget.onSelectAll?.call();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        // Save
        widget.onSave?.call();
        return;
      }
    }

    if (_isEditing) {
      // Handle editing mode keys
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _commitEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        _commitEdit();
        if (HardwareKeyboard.instance.isShiftPressed) {
          _moveToPreviousCell();
        } else {
          _moveToNextCell();
        }
      }
    } else {
      // Handle navigation mode keys
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          _moveUp();
          break;
        case LogicalKeyboardKey.arrowDown:
          _moveDown();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _moveLeft();
          break;
        case LogicalKeyboardKey.arrowRight:
          _moveRight();
          break;
        case LogicalKeyboardKey.tab:
          if (HardwareKeyboard.instance.isShiftPressed) {
            _moveToPreviousCell();
          } else {
            _moveToNextCell();
          }
          break;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.f2:
          _startEdit();
          break;
        case LogicalKeyboardKey.space:
          if (_focusedColumn == 0) {
            _toggleSelection();
          }
          break;
        case LogicalKeyboardKey.home:
          _moveToRowStart();
          break;
        case LogicalKeyboardKey.end:
          _moveToRowEnd();
          break;
        case LogicalKeyboardKey.pageUp:
          _pageUp();
          break;
        case LogicalKeyboardKey.pageDown:
          _pageDown();
          break;
      }
    }
  }

  void _moveUp() {
    setState(() {
      _focusedRow = (_focusedRow - 1).clamp(0, filteredItems.length - 1);
      _ensureVisible();
    });
  }

  void _moveDown() {
    setState(() {
      _focusedRow = (_focusedRow + 1).clamp(0, filteredItems.length - 1);
      _ensureVisible();
    });
  }

  void _moveLeft() {
    setState(() {
      _focusedColumn = (_focusedColumn - 1).clamp(0, columns.length - 1);
    });
  }

  void _moveRight() {
    setState(() {
      _focusedColumn = (_focusedColumn + 1).clamp(0, columns.length - 1);
    });
  }

  void _moveToNextCell() {
    setState(() {
      _focusedColumn++;
      if (_focusedColumn >= columns.length) {
        _focusedColumn = 0;
        _focusedRow = (_focusedRow + 1).clamp(0, filteredItems.length - 1);
      }
      _ensureVisible();
    });
  }

  void _moveToPreviousCell() {
    setState(() {
      _focusedColumn--;
      if (_focusedColumn < 0) {
        _focusedColumn = columns.length - 1;
        _focusedRow = (_focusedRow - 1).clamp(0, filteredItems.length - 1);
      }
      _ensureVisible();
    });
  }

  void _moveToRowStart() {
    setState(() {
      _focusedColumn = 0;
    });
  }

  void _moveToRowEnd() {
    setState(() {
      _focusedColumn = columns.length - 1;
    });
  }

  void _pageUp() {
    setState(() {
      _focusedRow = (_focusedRow - 10).clamp(0, filteredItems.length - 1);
      _ensureVisible();
    });
  }

  void _pageDown() {
    setState(() {
      _focusedRow = (_focusedRow + 10).clamp(0, filteredItems.length - 1);
      _ensureVisible();
    });
  }

  void _toggleSelection() {
    if (_focusedRow < filteredItems.length) {
      final item = filteredItems[_focusedRow];
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      widget.onItemSelected(itemId);
    }
  }

  void _startEdit() {
    if (!editableColumns.contains(_focusedColumn)) return;
    if (_focusedRow >= filteredItems.length) return;

    final item = filteredItems[_focusedRow];
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';

    String initialValue = '';

    switch (_focusedColumn) {
      case 3: // Brand
        initialValue = widget.editedBrandNames[itemId] ?? item.brandText;
        break;
      case 5: // Quantity
        initialValue = (widget.editedQuantities[itemId] ?? item.totalStock).toString();
        break;
      case 6: // Price
        initialValue = (widget.editedPrices[itemId] ?? item.sellingPrice).toString();
        break;
    }

    setState(() {
      _isEditing = true;
      _editController = TextEditingController(text: initialValue);
      _editFocusNode = FocusNode();

      // Select all text when starting edit
      _editController!.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController!.text.length,
      );
    });

    // Focus the edit field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode?.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_isEditing || _editController == null) return;

    final item = filteredItems[_focusedRow];
    final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
    final value = _editController!.text;

    switch (_focusedColumn) {
      case 3: // Brand
        widget.onBrandNameChanged(itemId, value);
        break;
      case 5: // Quantity
        final qty = int.tryParse(value) ?? 0;
        widget.onQuantityChanged(itemId, qty);
        break;
      case 6: // Price
        final price = double.tryParse(value) ?? 0.0;
        widget.onPriceChanged(itemId, price);
        break;
    }

    _cancelEdit();
    _calculateQualityScores();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editController?.dispose();
      _editController = null;
      _editFocusNode?.dispose();
      _editFocusNode = null;
    });
    _tableFocusNode.requestFocus();
  }

  void _ensureVisible() {
    // Calculate row height (approximate)
    const double rowHeight = 80.0;
    final double targetOffset = _focusedRow * rowHeight;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double currentOffset = _scrollController.offset;

    if (targetOffset < currentOffset) {
      // Scroll up
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    } else if (targetOffset + rowHeight > currentOffset + viewportHeight) {
      // Scroll down
      _scrollController.animateTo(
        targetOffset + rowHeight - viewportHeight,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KeyboardListener(
      focusNode: _tableFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // Keyboard shortcuts help bar
          _buildKeyboardShortcutsBar(),

          // Search and Filter Bar
          _buildSearchAndFilterBar(),

          // Data Quality Summary
          _buildDataQualitySummary(),

          // Table Header
          _buildTableHeader(),

          // Divider
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.3),
                  cs.primary.withValues(alpha: 0.1),
                ],
              ),
            ),
          ),

          // Table Body
          Expanded(
            child: _buildTableBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardShortcutsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: AppColors.info.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildShortcut('↑↓←→', 'Navigate'),
          _buildShortcut('Enter/F2', 'Edit'),
          _buildShortcut('Tab', 'Next Cell'),
          _buildShortcut('Esc', 'Cancel'),
          _buildShortcut('Space', 'Select'),
          _buildShortcut('Ctrl+A', 'Select All'),
          _buildShortcut('Ctrl+S', 'Save'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isEditing ? AppColors.warning : AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isEditing ? 'EDIT MODE' : 'NAVIGATE MODE',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcut(String keys, String action) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.onSurfaceVariant),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            action,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                onChanged: (value) {
                  _searchDebouncer?.cancel();
                  _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      searchQuery = value;
                    });
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search brands, sizes, prices...',
                  prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, size: 14),
                const SizedBox(width: 4),
                const Text('Issues Only'),
              ],
            ),
            selected: showOnlyIssues,
            onSelected: (selected) {
              setState(() {
                showOnlyIssues = selected;
              });
            },
            selectedColor: AppColors.warning.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _autoFixAll,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto-Fix All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataQualitySummary() {
    final totalItems = widget.items.length;
    final excellentItems = _qualityScores.values.where((s) => s.score >= 0.9).length;
    final goodItems = _qualityScores.values.where((s) => s.score >= 0.7 && s.score < 0.9).length;
    final poorItems = _qualityScores.values.where((s) => s.score < 0.7).length;
    final averageScore = _qualityScores.isEmpty
        ? 0.0
        : _qualityScores.values.map((s) => s.score).reduce((a, b) => a + b) / _qualityScores.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getQualityColor(averageScore).withValues(alpha: 0.1),
            _getQualityColor(averageScore).withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getQualityColor(averageScore).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getQualityColor(averageScore),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, color: _getQualityColor(averageScore), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Data Quality: ${(averageScore * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _getQualityColor(averageScore),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _buildQualityBadge('Excellent', excellentItems, AppColors.success),
          const SizedBox(width: 8),
          _buildQualityBadge('Good', goodItems, AppColors.warning),
          const SizedBox(width: 8),
          _buildQualityBadge('Poor', poorItems, AppColors.error),
        ],
      ),
    );
  }

  Widget _buildQualityBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildHeaderCell('', width: 50, icon: Icons.check_box_outline_blank, column: 0),
            _buildHeaderCell('#', width: 60, icon: Icons.numbers, column: 1),
            _buildHeaderCell('Quality', width: 80, icon: Icons.grade, column: 2),
            _buildHeaderCell('Brand Name', width: 200, icon: Icons.local_drink, column: 3),
            _buildHeaderCell('Size', width: 100, icon: Icons.straighten, column: 4),
            _buildHeaderCell('Qty', width: 120, icon: Icons.inventory_2, column: 5),
            _buildHeaderCell('Price', width: 100, icon: Icons.currency_rupee, column: 6),
            _buildHeaderCell('Status', width: 100, icon: Icons.info_outline, column: 7),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String title, {
    required double width,
    IconData? icon,
    required int column,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isFocused = !_isEditing && _focusedColumn == column;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isFocused ? cs.primary.withValues(alpha: 0.1) : null,
        border: isFocused
            ? Border(
                left: BorderSide(color: cs.primary, width: 2),
                right: BorderSide(color: cs.primary, width: 2),
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: isFocused ? cs.primary : cs.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
          ],
          if (title.isNotEmpty)
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isFocused ? cs.primary : cs.primary.withValues(alpha: 0.9),
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    final cs = Theme.of(context).colorScheme;
    final items = filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty
                  ? 'No items match your search'
                  : 'No items to display',
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: items.length,
      padding: const EdgeInsets.only(bottom: 80),
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
        final isFocusedRow = !_isEditing && index == _focusedRow;

        return _buildTableRow(item, itemId, index, isFocusedRow);
      },
    );
  }

  Widget _buildTableRow(DeduplicatedItem item, String itemId, int rowIndex, bool isFocusedRow) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = widget.selectedItemIds.contains(itemId);
    final isAccepted = widget.acceptanceStates[itemId] ?? false;
    final isRejected = widget.rejectionStates[itemId] ?? false;

    final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
    final quantity = widget.editedQuantities[itemId] ?? item.totalStock;
    final price = widget.editedPrices[itemId] ?? item.sellingPrice;

    final qualityScore = _qualityScores[itemId];
    final autoFix = _autoFixes[itemId];

    final rowColor = _getRowColor(isSelected, isAccepted, isRejected, item.matchConfidence, isFocusedRow);
    final borderColor = _getBorderColor(isSelected, isAccepted, isRejected, item.matchConfidence, isFocusedRow);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border.all(
          color: borderColor,
          width: isFocusedRow ? 2 : (isSelected ? 2 : 1),
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: isFocusedRow
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _focusedRow = rowIndex;
              _focusedColumn = 0;
            });
            widget.onItemSelected(itemId);
          },
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCell(0, rowIndex, _buildCheckboxContent(isSelected)),
                _buildCell(1, rowIndex, _buildRowNumberContent(item.rowNumber)),
                _buildCell(2, rowIndex, _buildQualityContent(qualityScore, autoFix != null)),
                _buildCell(3, rowIndex, _buildBrandContent(brandName, itemId), isEditable: true),
                _buildCell(4, rowIndex, _buildSizeContent(item.sizeText)),
                _buildCell(5, rowIndex, _buildQuantityContent(quantity, itemId), isEditable: true),
                _buildCell(6, rowIndex, _buildPriceContent(price, itemId, brandName, item.sizeText), isEditable: true),
                _buildCell(7, rowIndex, _buildStatusContent(isAccepted, isRejected)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(int column, int row, Widget content, {bool isEditable = false}) {
    final cs = Theme.of(context).colorScheme;
    final isFocused = !_isEditing && _focusedColumn == column && _focusedRow == row;
    final isEditingThisCell = _isEditing && _focusedColumn == column && _focusedRow == row;

    double width;
    switch (column) {
      case 0: width = 50; break;
      case 1: width = 60; break;
      case 2: width = 80; break;
      case 3: width = 200; break;
      case 4: width = 100; break;
      case 5: width = 120; break;
      case 6: width = 100; break;
      case 7: width = 100; break;
      default: width = 100;
    }

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isFocused
            ? cs.primary.withValues(alpha: 0.15)
            : isEditingThisCell
                ? AppColors.warning.withValues(alpha: 0.1)
                : null,
        border: isFocused || isEditingThisCell
            ? Border(
                left: BorderSide(
                  color: isEditingThisCell ? AppColors.warning : cs.primary,
                  width: 2,
                ),
                right: BorderSide(
                  color: isEditingThisCell ? AppColors.warning : cs.primary,
                  width: 2,
                ),
              )
            : null,
      ),
      child: isEditingThisCell && _editController != null
          ? TextField(
              controller: _editController,
              focusNode: _editFocusNode,
              onSubmitted: (_) => _commitEdit(),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(),
              ),
            )
          : content,
    );
  }

  Widget _buildCheckboxContent(bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          border: Border.all(
            color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _buildRowNumberContent(int? rowNumber) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            rowNumber != null ? '#$rowNumber' : '-',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityContent(DataQualityScore? score, bool hasAutoFix) {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _getQualityColor(score?.score ?? 1.0),
                width: 3,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score?.grade ?? 'A',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _getQualityColor(score?.score ?? 1.0),
                    ),
                  ),
                  Text(
                    '${((score?.score ?? 1.0) * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _getQualityColor(score?.score ?? 1.0),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasAutoFix)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.info,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_fix_high,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrandContent(String brandName, String itemId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          brandName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSizeContent(String size) {
    final normalizedSize = BrandIntelligenceService.normalizeSize(size);
    return Center(
      child: Text(
        normalizedSize,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQuantityContent(int quantity, String itemId) {
    return Center(
      child: Text(
        quantity.toString(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPriceContent(double? price, String itemId, String brandName, String size) {
    if (price == null) return const Center(child: Text('-'));

    final validation = BrandIntelligenceService.validatePrice(
      brand: brandName,
      size: size,
      price: price,
    );

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: validation.isValid
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: validation.isValid
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.warning.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          '₹${price.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: validation.isValid ? AppColors.success : AppColors.warning,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusContent(bool isAccepted, bool isRejected) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isRejected) {
      statusText = 'Rejected';
      statusColor = AppColors.error;
      statusIcon = Icons.cancel;
    } else if (isAccepted) {
      statusText = 'Accepted';
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
    } else {
      statusText = 'Pending';
      statusColor = AppColors.warning;
      statusIcon = Icons.pending;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 12, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getQualityColor(double score) {
    if (score >= 0.9) return AppColors.success;
    if (score >= 0.7) return AppColors.warning;
    return AppColors.error;
  }

  Color _getRowColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, bool isFocused) {
    final cs = Theme.of(context).colorScheme;
    if (isFocused) {
      return cs.primary.withValues(alpha: 0.08);
    }
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.08);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.08);
    }
    if (isSelected) {
      return cs.primary.withValues(alpha: 0.08);
    }

    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.05);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.05);
    } else {
      return AppColors.error.withValues(alpha: 0.05);
    }
  }

  Color _getBorderColor(bool isSelected, bool isAccepted, bool isRejected, double confidence, bool isFocused) {
    final cs = Theme.of(context).colorScheme;
    if (isFocused) {
      return cs.primary;
    }
    if (isRejected) {
      return AppColors.error.withValues(alpha: 0.3);
    }
    if (isAccepted) {
      return AppColors.success.withValues(alpha: 0.3);
    }
    if (isSelected) {
      return cs.primary;
    }

    if (confidence >= 0.8) {
      return AppColors.success.withValues(alpha: 0.2);
    } else if (confidence >= 0.5) {
      return AppColors.warning.withValues(alpha: 0.2);
    } else {
      return AppColors.error.withValues(alpha: 0.2);
    }
  }

  void _autoFixAll() {
    int fixedCount = 0;

    for (final item in widget.items) {
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      if (itemId.isEmpty) continue;

      final brandName = widget.editedBrandNames[itemId] ?? item.brandText;
      final price = widget.editedPrices[itemId] ?? item.sellingPrice;

      final autoFix = BrandIntelligenceService.autoFixItem(
        brandText: brandName,
        sizeText: item.sizeText,
        price: price,
      );

      if (autoFix.hasChanges) {
        _autoFixes[itemId] = autoFix;
        widget.onBrandNameChanged(itemId, autoFix.brandText);
        if (autoFix.price != null && autoFix.price != price) {
          widget.onPriceChanged(itemId, autoFix.price!);
        }
        fixedCount++;
      }
    }

    if (fixedCount > 0) {
      setState(() {
        _calculateQualityScores();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Colors.white),
              const SizedBox(width: 8),
              Text('Auto-fixed $fixedCount items'),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}