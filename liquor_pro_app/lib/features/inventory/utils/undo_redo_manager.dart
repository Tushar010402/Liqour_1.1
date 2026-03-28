import 'dart:collection';

/// Undo/Redo Manager for OCR Review Workflow
///
/// FEATURES:
/// - Stack-based history (max 10 steps)
/// - Efficient memory usage (only stores acceptance state)
/// - Undo/redo support with clear API
/// - Can be extended to support checkpoints
///
/// USAGE:
/// ```dart
/// final manager = UndoRedoManager<AcceptanceSnapshot>();
///
/// // Save state before action
/// manager.record(AcceptanceSnapshot(
///   acceptedIds: currentAccepted,
///   rejectedIds: currentRejected,
/// ));
///
/// // Undo
/// if (manager.canUndo) {
///   final previous = manager.undo();
///   // Restore state from previous
/// }
///
/// // Redo
/// if (manager.canRedo) {
///   final next = manager.redo();
///   // Restore state from next
/// }
/// ```
class UndoRedoManager<T> {
  final int maxHistorySize;

  /// History stack (past states)
  final Queue<T> _undoStack = Queue();

  /// Future stack (undone states that can be redone)
  final Queue<T> _redoStack = Queue();

  UndoRedoManager({
    this.maxHistorySize = 10,
  });

  /// Record a new state (before making changes)
  void record(T state) {
    // Add to undo stack
    _undoStack.addLast(state);

    // Limit history size
    if (_undoStack.length > maxHistorySize) {
      _undoStack.removeFirst();
    }

    // Clear redo stack (new action invalidates future)
    _redoStack.clear();
  }

  /// Undo: Move current state to redo stack and return previous state
  T? undo() {
    if (!canUndo) return null;

    // Get previous state
    final previous = _undoStack.removeLast();
    return previous;
  }

  /// Redo: Restore a previously undone state
  T? redo() {
    if (!canRedo) return null;

    // Get next state
    final next = _redoStack.removeLast();
    return next;
  }

  /// Move current state to redo stack (for undo operation)
  void pushToRedo(T currentState) {
    _redoStack.addLast(currentState);

    // Limit redo stack size
    if (_redoStack.length > maxHistorySize) {
      _redoStack.removeFirst();
    }
  }

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get number of undo steps available
  int get undoCount => _undoStack.length;

  /// Get number of redo steps available
  int get redoCount => _redoStack.length;

  /// Clear all history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Clear only redo stack (used when recording new action)
  void clearRedo() {
    _redoStack.clear();
  }

  /// Get all undo states (for debugging/visualization)
  List<T> get undoHistory => _undoStack.toList();

  /// Get all redo states (for debugging/visualization)
  List<T> get redoHistory => _redoStack.toList();
}

/// Snapshot of acceptance state for undo/redo
class AcceptanceSnapshot {
  final Set<String> acceptedIds;
  final Set<String> rejectedIds;
  final DateTime timestamp;

  AcceptanceSnapshot({
    required this.acceptedIds,
    required this.rejectedIds,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a copy with modifications
  AcceptanceSnapshot copyWith({
    Set<String>? acceptedIds,
    Set<String>? rejectedIds,
  }) {
    return AcceptanceSnapshot(
      acceptedIds: acceptedIds ?? this.acceptedIds,
      rejectedIds: rejectedIds ?? this.rejectedIds,
      timestamp: timestamp,
    );
  }

  /// Create from current state
  factory AcceptanceSnapshot.fromSets(
    Set<String> acceptedIds,
    Set<String> rejectedIds,
  ) {
    return AcceptanceSnapshot(
      // Create copies to avoid reference issues
      acceptedIds: Set<String>.from(acceptedIds),
      rejectedIds: Set<String>.from(rejectedIds),
    );
  }

  @override
  String toString() {
    return 'AcceptanceSnapshot(accepted: ${acceptedIds.length}, rejected: ${rejectedIds.length}, time: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AcceptanceSnapshot &&
        other.acceptedIds.length == acceptedIds.length &&
        other.rejectedIds.length == rejectedIds.length &&
        other.acceptedIds.every((id) => acceptedIds.contains(id)) &&
        other.rejectedIds.every((id) => rejectedIds.contains(id));
  }

  @override
  int get hashCode => acceptedIds.hashCode ^ rejectedIds.hashCode;
}
