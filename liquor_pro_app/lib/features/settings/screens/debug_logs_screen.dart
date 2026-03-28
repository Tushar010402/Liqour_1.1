import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/debug_log_service.dart';

/// Debug Logs Screen - View and filter app logs in real-time
///
/// Features:
/// - Real-time log updates
/// - Filter by tag (Scanner, Auth, API, etc.)
/// - Filter by level (Error, Warning, Info, Debug)
/// - Search logs
/// - Export/Share logs
/// - Copy individual log entries
class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  final DebugLogService _logService = DebugLogService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<LogEntry>? _logSubscription;
  List<LogEntry> _filteredLogs = [];

  // Filters
  String? _selectedTag;
  LogLevel? _selectedLevel;
  String _searchQuery = '';
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _updateFilteredLogs();

    // Listen for new logs
    _logSubscription = _logService.logStream.listen((entry) {
      _updateFilteredLogs();
      if (_autoScroll && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Log that we opened the debug screen
    DebugLogService.info('DebugLogs', 'Debug logs screen opened');
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilteredLogs() {
    setState(() {
      _filteredLogs = _logService.filterLogs(
        tag: _selectedTag,
        level: _selectedLevel,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
    });
  }

  Color _getLevelColor(BuildContext context, LogLevel level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case LogLevel.debug: return cs.onSurfaceVariant;
      case LogLevel.info: return Colors.blue;
      case LogLevel.warning: return Colors.orange;
      case LogLevel.error: return Colors.red;
      case LogLevel.success: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final counts = _logService.logCountByLevel;

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: cs.onSurface,
        foregroundColor: Colors.white,
        title: const Text(
          'Debug Logs',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          // Auto-scroll toggle
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? Colors.green : cs.onSurfaceVariant,
            ),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              HapticFeedback.lightImpact();
            },
          ),
          // Share logs
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Logs',
            onPressed: _shareLogs,
          ),
          // Clear logs
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Logs',
            onPressed: _confirmClearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.onSurface,
            child: Row(
              children: [
                _buildStatChip('All', _logService.allLogs.length, Colors.white),
                const SizedBox(width: 8),
                _buildStatChip('E', counts[LogLevel.error] ?? 0, Colors.red),
                const SizedBox(width: 8),
                _buildStatChip('W', counts[LogLevel.warning] ?? 0, Colors.orange),
                const SizedBox(width: 8),
                _buildStatChip('I', counts[LogLevel.info] ?? 0, Colors.blue),
                const SizedBox(width: 8),
                _buildStatChip('S', counts[LogLevel.success] ?? 0, Colors.green),
                const Spacer(),
                Text(
                  'Showing ${_filteredLogs.length}',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Filter bar
          Container(
            padding: const EdgeInsets.all(12),
            color: cs.surface,
            child: Column(
              children: [
                // Search field
                CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Search logs...',
                  onChanged: (value) {
                    _searchQuery = value;
                    _updateFilteredLogs();
                  },
                ),
                const SizedBox(height: 12),
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Level filter
                      _buildFilterChip(
                        label: _selectedLevel?.name.toUpperCase() ?? 'All Levels',
                        isSelected: _selectedLevel != null,
                        onTap: _showLevelFilter,
                        color: _selectedLevel != null ? _getLevelColor(context, _selectedLevel!) : null,
                      ),
                      const SizedBox(width: 8),
                      // Tag filter
                      _buildFilterChip(
                        label: _selectedTag ?? 'All Tags',
                        isSelected: _selectedTag != null,
                        onTap: _showTagFilter,
                      ),
                      const SizedBox(width: 8),
                      // Quick filters
                      _buildQuickFilterChip('Scanner', 'Scanner'),
                      const SizedBox(width: 8),
                      _buildQuickFilterChip('API', 'API'),
                      const SizedBox(width: 8),
                      _buildQuickFilterChip('Auth', 'Auth'),
                      const SizedBox(width: 8),
                      _buildQuickFilterChip('Sales', 'Sales'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Log list
          Expanded(
            child: _filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: cs.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No logs found',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        if (_selectedTag != null || _selectedLevel != null || _searchQuery.isNotEmpty)
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Clear Filters'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = _filteredLogs[index];
                      return _buildLogEntry(log);
                    },
                  ),
          ),
        ],
      ),
      // FAB to scroll to bottom
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        backgroundColor: cs.onSurface,
        child: const Icon(Icons.arrow_downward, color: Colors.white),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (color ?? Colors.blue).withOpacity(0.1) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? (color ?? Colors.blue) : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? (color ?? Colors.blue) : cs.onSurface,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.close,
                size: 14,
                color: color ?? Colors.blue,
              ),
            ] else ...[
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterChip(String label, String tag) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedTag == tag;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTag = isSelected ? null : tag;
        });
        _updateFilteredLogs();
        HapticFeedback.lightImpact();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.blue : cs.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: () => _copyLog(log),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: _getLevelColor(context, log.level),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Text(
                  log.formattedTime,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getLevelColor(context, log.level).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.levelName,
                    style: TextStyle(
                      color: _getLevelColor(context, log.level),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.tag,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copyLog(log),
                  child: Icon(
                    Icons.copy,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Message
            Text(
              log.message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
              ),
            ),
            // Stack trace (if any)
            if (log.stackTrace != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  log.stackTrace!,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.red.shade800,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLevelFilter() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Filter by Level'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _selectedLevel = null);
              _updateFilteredLogs();
            },
            child: const Text('All Levels'),
          ),
          ...LogLevel.values.map((level) => CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _selectedLevel = level);
              _updateFilteredLogs();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getLevelColor(context, level),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(level.name.toUpperCase()),
              ],
            ),
          )),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showTagFilter() {
    final tags = _logService.uniqueTags;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Filter by Tag'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _selectedTag = null);
              _updateFilteredLogs();
            },
            child: const Text('All Tags'),
          ),
          ...tags.map((tag) => CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _selectedTag = tag);
              _updateFilteredLogs();
            },
            child: Text(tag),
          )),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedTag = null;
      _selectedLevel = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _updateFilteredLogs();
  }

  void _copyLog(LogEntry log) {
    Clipboard.setData(ClipboardData(text: log.toString()));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _shareLogs() async {
    final logs = await _logService.exportLogs(
      tag: _selectedTag,
      level: _selectedLevel,
    );

    await Share.share(
      logs,
      subject: 'LiquorPro Debug Logs',
    );
  }

  void _confirmClearLogs() {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to clear all logs?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              DebugLogService.clearLogs();
              _updateFilteredLogs();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
