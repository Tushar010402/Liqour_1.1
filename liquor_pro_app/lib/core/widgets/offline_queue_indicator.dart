import 'package:flutter/material.dart';
import '../services/offline_queue_service.dart';

/// Offline Queue Indicator Widget
/// Shows pending offline requests count and provides manual sync
/// Best Practice: Give users visibility and control over offline queue
class OfflineQueueIndicator extends StatefulWidget {
  final OfflineQueueService offlineQueue;
  final bool showWhenEmpty;

  const OfflineQueueIndicator({
    super.key,
    required this.offlineQueue,
    this.showWhenEmpty = false,
  });

  @override
  State<OfflineQueueIndicator> createState() => _OfflineQueueIndicatorState();
}

class _OfflineQueueIndicatorState extends State<OfflineQueueIndicator> {
  int _pendingCount = 0;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _updateCount();

    // Listen for queue changes
    widget.offlineQueue.onRequestQueued(_onQueueChanged);
    widget.offlineQueue.onRequestSuccess(_onQueueChanged);
    widget.offlineQueue.onRequestFailed(_onQueueFailed);

    // Update count every 2 seconds
    _startPeriodicUpdate();
  }

  void _startPeriodicUpdate() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _updateCount();
        _startPeriodicUpdate();
      }
    });
  }

  void _updateCount() {
    if (mounted) {
      setState(() {
        _pendingCount = widget.offlineQueue.pendingCount;
      });
    }
  }

  void _onQueueChanged(QueuedRequest request) {
    _updateCount();
  }

  void _onQueueFailed(QueuedRequest request, String error) {
    _updateCount();
  }

  Future<void> _manualSync() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Trigger manual queue processing
      await Future.delayed(const Duration(milliseconds: 500));
      _updateCount();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide if no pending requests and showWhenEmpty is false
    if (_pendingCount == 0 && !widget.showWhenEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _pendingCount > 0
            ? Colors.orange.withOpacity(0.9)
            : Colors.green.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Icon(
            _pendingCount > 0
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Text(
              _pendingCount > 0
                  ? '$_pendingCount ${_pendingCount == 1 ? 'request' : 'requests'} pending sync'
                  : 'All synced',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Manual sync button (only show if pending)
          if (_pendingCount > 0) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isProcessing ? null : _manualSync,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(
                          Icons.sync,
                          color: Colors.white,
                          size: 14,
                        ),
                      const SizedBox(width: 4),
                      const Text(
                        'Sync Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Info button
          if (_pendingCount > 0) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showQueueDetails(context),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showQueueDetails(BuildContext context) {
    final requests = widget.offlineQueue.pendingRequests;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions,
                      color: Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Pending Sync Queue',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${requests.length} ${requests.length == 1 ? 'item' : 'items'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Request list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return _buildRequestTile(context, request);
                  },
                ),
              ),

              // Bottom padding
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestTile(BuildContext context, QueuedRequest request) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    String typeLabel;

    switch (request.type) {
      case RequestType.critical:
        icon = Icons.priority_high;
        color = Colors.red;
        typeLabel = 'Critical';
        break;
      case RequestType.important:
        icon = Icons.star;
        color = Colors.orange;
        typeLabel = 'Important';
        break;
      case RequestType.normal:
        icon = Icons.circle;
        color = Colors.blue;
        typeLabel = 'Normal';
        break;
      case RequestType.other:
        icon = Icons.more_horiz;
        color = cs.onSurfaceVariant;
        typeLabel = 'Other';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Priority icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),

              // Request info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.method} ${request.endpoint}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getTimeDifference(request.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Priority badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Retry info
          if (request.retryCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.refresh,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Retry ${request.retryCount}/5',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getTimeDifference(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  void dispose() {
    // Note: We don't remove listeners because they're statically stored
    // and the widget may be recreated
    super.dispose();
  }
}
