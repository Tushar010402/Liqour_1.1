import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cash_models.dart';

/// Real-time countdown timer widget for cash collection expiration
class CountdownTimerWidget extends StatefulWidget {
  final CashCollection collection;
  final VoidCallback? onExpired;

  const CountdownTimerWidget({
    super.key,
    required this.collection,
    this.onExpired,
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    setState(() {
      _remaining = widget.collection.timeRemaining;
    });

    // Check if expired
    if (widget.collection.hasExpired && widget.onExpired != null) {
      widget.onExpired!();
    }
  }

  void _startTimer() {
    // Update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemaining();

      // Stop timer if expired
      if (widget.collection.hasExpired) {
        _timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == null || widget.collection.hasExpired) {
      return _buildExpiredIndicator();
    }

    final minutes = _remaining!.inMinutes;
    final seconds = _remaining!.inSeconds % 60;
    final isUrgent = minutes < 3; // Less than 3 minutes remaining

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent ? Colors.red.shade300 : Colors.orange.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: isUrgent ? Colors.red.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            '$minutes:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isUrgent ? Colors.red.shade700 : Colors.orange.shade700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredIndicator() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_filled,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'Expired',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
