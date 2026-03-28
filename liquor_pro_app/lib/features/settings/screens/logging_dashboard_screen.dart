import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/logging/logging.dart';

/// Industrial-Grade Logging Dashboard
///
/// Comprehensive logging system with:
/// - Live logs with filtering
/// - Network inspector (API calls)
/// - Session history
/// - Sync status and settings
class LoggingDashboardScreen extends StatefulWidget {
  const LoggingDashboardScreen({super.key});

  @override
  State<LoggingDashboardScreen> createState() => _LoggingDashboardScreenState();
}

class _LoggingDashboardScreenState extends State<LoggingDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LoggingService _loggingService = LoggingService.instance;
  final LogSyncService _syncService = LogSyncService();
  final LogDatabase _db = LogDatabase();

  // State
  List<LogEntry> _logs = [];
  List<Map<String, dynamic>> _networkRequests = [];
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _syncStats;
  StreamSubscription<LogEntry>? _logSubscription;
  StreamSubscription<SyncStatus>? _syncSubscription;

  // Filters
  LogLevel? _selectedLevel;
  String? _selectedTag;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    // Listen for new logs
    _logSubscription = _loggingService.logStream.listen((entry) {
      setState(() {
        _logs = _loggingService.getFilteredLogs(
          level: _selectedLevel,
          tag: _selectedTag,
          search: _searchQuery.isEmpty ? null : _searchQuery,
        );
      });
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

    // Listen for sync status changes
    _syncSubscription = _syncService.statusStream.listen((_) {
      _loadSyncStats();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    switch (_tabController.index) {
      case 0:
        _loadLogs();
        break;
      case 1:
        _loadNetworkRequests();
        break;
      case 2:
        _loadSessions();
        break;
      case 3:
        _loadSyncStats();
        break;
    }
  }

  void _loadLogs() {
    setState(() {
      _logs = _loggingService.getFilteredLogs(
        level: _selectedLevel,
        tag: _selectedTag,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
    });
  }

  Future<void> _loadNetworkRequests() async {
    final requests = await _db.getNetworkRequests(limit: 100);
    setState(() {
      _networkRequests = requests;
    });
  }

  Future<void> _loadSessions() async {
    final sessions = await _db.getSessions(limit: 50);
    setState(() {
      _sessions = sessions;
    });
  }

  Future<void> _loadSyncStats() async {
    final stats = await _syncService.getSyncStats();
    setState(() {
      _syncStats = stats;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logSubscription?.cancel();
    _syncSubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _getLevelColor(BuildContext context, LogLevel level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case LogLevel.debug:
        return cs.onSurfaceVariant;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.success:
        return Colors.green;
    }
  }

  Color _getStatusColor(BuildContext context, int? statusCode) {
    if (statusCode == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400 && statusCode < 500) return Colors.orange;
    if (statusCode >= 500) return Colors.red;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: cs.onSurface,
        foregroundColor: Colors.white,
        title: const Text(
          'Logging Dashboard',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportLogs();
                  break;
                case 'clear':
                  _confirmClearLogs();
                  break;
                case 'sync_now':
                  _syncService.syncNow();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.share, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Text('Export Logs'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sync_now',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Text('Sync Now'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear Logs', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.article), text: 'Logs'),
            Tab(icon: Icon(Icons.wifi), text: 'Network'),
            Tab(icon: Icon(Icons.history), text: 'Sessions'),
            Tab(icon: Icon(Icons.sync), text: 'Sync'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLogsTab(),
          _buildNetworkTab(),
          _buildSessionsTab(),
          _buildSyncTab(),
        ],
      ),
    );
  }

  // ==================== LOGS TAB ====================
  Widget _buildLogsTab() {
    final cs = Theme.of(context).colorScheme;
    final counts = _loggingService.logCountByLevel;

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.onSurface,
          child: Row(
            children: [
              _buildStatChip('All', _loggingService.recentLogs.length, Colors.white),
              const SizedBox(width: 8),
              _buildStatChip('E', counts[LogLevel.error] ?? 0, Colors.red),
              const SizedBox(width: 8),
              _buildStatChip('W', counts[LogLevel.warning] ?? 0, Colors.orange),
              const SizedBox(width: 8),
              _buildStatChip('I', counts[LogLevel.info] ?? 0, Colors.blue),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
                  color: _autoScroll ? Colors.green : cs.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _autoScroll = !_autoScroll);
                  HapticFeedback.lightImpact();
                },
                tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
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
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search logs...',
                onChanged: (value) {
                  _searchQuery = value;
                  _loadLogs();
                },
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: _selectedLevel?.name.toUpperCase() ?? 'All Levels',
                      isSelected: _selectedLevel != null,
                      onTap: _showLevelFilter,
                      color: _selectedLevel != null ? _getLevelColor(context, _selectedLevel!) : null,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: _selectedTag ?? 'All Tags',
                      isSelected: _selectedTag != null,
                      onTap: _showTagFilter,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip('API', 'API'),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip('Nav', 'Navigation'),
                    const SizedBox(width: 8),
                    _buildQuickFilterChip('Auth', 'Auth'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Log list
        Expanded(
          child: _logs.isEmpty
              ? _buildEmptyState('No logs found', 'Logs will appear here as you use the app')
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return _buildLogEntry(log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: () => _copyToClipboard(log.toString()),
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
            Row(
              children: [
                Text(
                  _formatTime(log.timestamp),
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
                    log.level.name.toUpperCase(),
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
              ],
            ),
            const SizedBox(height: 6),
            Text(
              log.message,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
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

  // ==================== NETWORK TAB ====================
  Widget _buildNetworkTab() {
    return _networkRequests.isEmpty
        ? _buildEmptyState('No network requests', 'API calls will be logged here')
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _networkRequests.length,
            itemBuilder: (context, index) {
              final request = _networkRequests[index];
              return _buildNetworkRequestCard(request);
            },
          );
  }

  Widget _buildNetworkRequestCard(Map<String, dynamic> request) {
    final method = request['method'] as String? ?? 'GET';
    final url = request['url'] as String? ?? '';
    final statusCode = request['status_code'] as int?;
    final durationMs = request['duration_ms'] as int?;
    final timestamp = request['timestamp'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getMethodColor(method).withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            method,
            style: TextStyle(
              color: _getMethodColor(method),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          _shortenUrl(url),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (statusCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getStatusColor(context, statusCode).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$statusCode',
                  style: TextStyle(
                    color: _getStatusColor(context, statusCode),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            if (durationMs != null)
              Text(
                '${durationMs}ms',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            const Spacer(),
            if (timestamp != null)
              Text(
                _formatTimestamp(timestamp),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailSection('URL', url),
                if (request['request_headers'] != null)
                  _buildDetailSection('Request Headers', request['request_headers']),
                if (request['request_body'] != null)
                  _buildDetailSection('Request Body', request['request_body']),
                if (request['response_headers'] != null)
                  _buildDetailSection('Response Headers', request['response_headers']),
                if (request['response_body'] != null)
                  _buildDetailSection('Response Body', request['response_body']),
                if (request['error_message'] != null)
                  _buildDetailSection('Error', request['error_message'], isError: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, String content, {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: isError ? Colors.red : cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isError ? Colors.red.shade50 : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isError ? Colors.red.shade800 : cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ==================== SESSIONS TAB ====================
  Widget _buildSessionsTab() {
    return _sessions.isEmpty
        ? _buildEmptyState('No sessions', 'Session history will appear here')
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _sessions.length,
            itemBuilder: (context, index) {
              final session = _sessions[index];
              return _buildSessionCard(session);
            },
          );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final startedAt = session['started_at'] as String?;
    final endedAt = session['ended_at'] as String?;
    final logCount = session['log_count'] as int? ?? 0;
    final errorCount = session['error_count'] as int? ?? 0;
    final appVersion = session['app_version'] as String? ?? 'Unknown';
    final isCurrent = endedAt == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrent ? Colors.green.shade100 : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            isCurrent ? Icons.play_arrow : Icons.stop,
            color: isCurrent ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          isCurrent ? 'Current Session' : _formatTimestamp(startedAt ?? ''),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            Icon(Icons.article, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('$logCount logs', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            if (errorCount > 0) ...[
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
              const SizedBox(width: 4),
              Text('$errorCount errors', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ],
            const Spacer(),
            Text('v$appVersion', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        trailing: isCurrent
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  // ==================== SYNC TAB ====================
  Widget _buildSyncTab() {
    final stats = _syncStats;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Sync Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getSyncStatusIcon(_syncService.status),
                      color: _getSyncStatusColor(_syncService.status),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sync Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getSyncStatusColor(_syncService.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _syncService.status.name.toUpperCase(),
                        style: TextStyle(
                          color: _getSyncStatusColor(_syncService.status),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (stats != null) ...[
                  _buildSyncStatRow('Total Logs', '${stats['total_logs'] ?? 0}'),
                  _buildSyncStatRow('Synced', '${stats['synced_logs'] ?? 0}'),
                  _buildSyncStatRow('Pending', '${stats['unsynced_logs'] ?? 0}',
                      highlight: (stats['unsynced_logs'] ?? 0) > 0),
                  if (stats['last_sync'] != null)
                    _buildSyncStatRow('Last Sync', _formatTimestamp(stats['last_sync'])),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Sync Button
        ElevatedButton.icon(
          onPressed: () async {
            await _syncService.syncNow();
            _loadSyncStats();
          },
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Sync Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 24),

        // Settings Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enable Sync'),
                  subtitle: const Text('Automatically sync logs to server'),
                  value: _syncService.syncEnabled,
                  onChanged: (value) async {
                    await _syncService.setSyncEnabled(value);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('WiFi Only'),
                  subtitle: const Text('Only sync when connected to WiFi'),
                  value: _syncService.wifiOnlySync,
                  onChanged: (value) async {
                    await _syncService.setWifiOnlySync(value);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Retention Info
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Logs are retained locally for 7 days. Synced logs are backed up to the server.',
                    style: TextStyle(
                      color: Colors.amber.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStatRow(String label, String value, {bool highlight = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: highlight ? Colors.orange : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================
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
            const SizedBox(width: 4),
            Icon(
              isSelected ? Icons.close : Icons.arrow_drop_down,
              size: isSelected ? 14 : 16,
              color: isSelected ? (color ?? Colors.blue) : cs.onSurfaceVariant,
            ),
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
        _loadLogs();
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

  Widget _buildEmptyState(String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
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
              _loadLogs();
            },
            child: const Text('All Levels'),
          ),
          ...LogLevel.values.map((level) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _selectedLevel = level);
                  _loadLogs();
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
    final tags = _loggingService.uniqueTags;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Filter by Tag'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _selectedTag = null);
              _loadLogs();
            },
            child: const Text('All Tags'),
          ),
          ...tags.map((tag) => CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _selectedTag = tag);
                  _loadLogs();
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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _exportLogs() async {
    final logs = await _loggingService.exportLogs(
      level: _selectedLevel,
      tag: _selectedTag,
    );

    await Share.share(
      logs,
      subject: 'LiquorPro Logs Export',
    );
  }

  void _confirmClearLogs() {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to clear all logs? This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              await _loggingService.clearAllLogs();
              _loadData();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.day}/${dt.month} ${_formatTime(dt)}';
    } catch (e) {
      return isoString;
    }
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path + (uri.query.isNotEmpty ? '?...' : '');
    } catch (e) {
      return url;
    }
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return Colors.green;
      case 'POST':
        return Colors.blue;
      case 'PUT':
        return Colors.orange;
      case 'PATCH':
        return Colors.amber;
      case 'DELETE':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getSyncStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Icons.cloud_queue;
      case SyncStatus.syncing:
        return Icons.cloud_upload;
      case SyncStatus.success:
        return Icons.cloud_done;
      case SyncStatus.failed:
        return Icons.cloud_off;
      case SyncStatus.offline:
        return Icons.wifi_off;
    }
  }

  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
      case SyncStatus.offline:
        return Colors.orange;
    }
  }
}
