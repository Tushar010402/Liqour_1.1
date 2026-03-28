import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';
import 'dio_api_service.dart';

/// Queued Request Model
class QueuedRequest {
  final String id;
  final String method; // GET, POST, PUT, DELETE
  final String endpoint;
  final Map<String, dynamic>? body;
  final Map<String, dynamic>? queryParams;
  final int retryCount;
  final int priority; // Higher = more important
  final DateTime createdAt;
  final DateTime? lastAttempt;
  final RequestType type;

  QueuedRequest({
    required this.id,
    required this.method,
    required this.endpoint,
    this.body,
    this.queryParams,
    this.retryCount = 0,
    this.priority = 1,
    required this.createdAt,
    this.lastAttempt,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'endpoint': endpoint,
        'body': body,
        'query_params': queryParams,
        'retry_count': retryCount,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'last_attempt': lastAttempt?.toIso8601String(),
        'type': type.toString(),
      };

  factory QueuedRequest.fromJson(Map<String, dynamic> json) {
    return QueuedRequest(
      id: json['id'] as String,
      method: json['method'] as String,
      endpoint: json['endpoint'] as String,
      body: json['body'] as Map<String, dynamic>?,
      queryParams: json['query_params'] as Map<String, dynamic>?,
      retryCount: json['retry_count'] as int? ?? 0,
      priority: json['priority'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastAttempt: json['last_attempt'] != null
          ? DateTime.parse(json['last_attempt'] as String)
          : null,
      type: RequestType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => RequestType.other,
      ),
    );
  }

  QueuedRequest copyWith({
    int? retryCount,
    DateTime? lastAttempt,
  }) {
    return QueuedRequest(
      id: id,
      method: method,
      endpoint: endpoint,
      body: body,
      queryParams: queryParams,
      retryCount: retryCount ?? this.retryCount,
      priority: priority,
      createdAt: createdAt,
      lastAttempt: lastAttempt ?? this.lastAttempt,
      type: type,
    );
  }
}

/// Request Types for prioritization
enum RequestType {
  critical, // Sale creation, payment processing
  important, // Stock updates, price changes
  normal, // Product edits, user updates
  other, // Everything else
}

/// Offline Request Queue Service
///
/// Queues failed requests and retries them when connection is restored
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  Box? _queueBox;
  bool _isInitialized = false;
  bool _isProcessing = false;
  DioApiService? _apiService;
  Timer? _retryTimer;

  final _uuid = const Uuid();
  final _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;

  // Callbacks
  final List<Function(QueuedRequest)> _onRequestQueued = [];
  final List<Function(QueuedRequest)> _onRequestSuccess = [];
  final List<Function(QueuedRequest, String)> _onRequestFailed = [];

  // Configuration
  static const int maxRetries = 5;
  static const Duration initialRetryDelay = Duration(seconds: 5);
  static const Duration maxRetryDelay = Duration(minutes: 5);
  static const Duration queueProcessInterval = Duration(seconds: 10);

  /// Initialize offline queue
  Future<void> initialize(DioApiService apiService) async {
    if (_isInitialized) return;

    try {
      _apiService = apiService;
      _queueBox = await Hive.openBox('offline_queue');
      _isInitialized = true;

      AppLogger.info('✅ [OfflineQueue] Initialized with ${_queueBox!.length} pending requests');

      // Start connectivity monitoring
      _startConnectivityMonitoring();

      // Start periodic queue processing
      _startQueueProcessing();
    } catch (e) {
      AppLogger.error('[OfflineQueue] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Queue a request for offline execution
  Future<String> queueRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
    int priority = 1,
    RequestType type = RequestType.normal,
  }) async {
    _ensureInitialized();

    final request = QueuedRequest(
      id: _uuid.v4(),
      method: method.toUpperCase(),
      endpoint: endpoint,
      body: body,
      queryParams: queryParams,
      priority: priority,
      createdAt: DateTime.now(),
      type: type,
    );

    await _queueBox!.put(request.id, request.toJson());

    AppLogger.info('[OfflineQueue] ➕ Queued request: $method $endpoint (${request.id.substring(0, 8)})');

    // Notify listeners
    for (final callback in _onRequestQueued) {
      callback(request);
    }

    // Try to process immediately
    _processQueue();

    return request.id;
  }

  /// Start monitoring connectivity changes
  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final isConnected = results.isNotEmpty &&
                           results.any((result) => result != ConnectivityResult.none);

        if (isConnected && _queueBox!.isNotEmpty) {
          AppLogger.info('[OfflineQueue] 📡 Connection restored - processing queue');
          _processQueue();
        }
      },
    );
  }

  /// Start periodic queue processing
  void _startQueueProcessing() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(queueProcessInterval, (_) {
      if (_queueBox!.isNotEmpty && !_isProcessing) {
        _processQueue();
      }
    });
  }

  /// Process the offline queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queueBox!.isEmpty) return;

    _isProcessing = true;

    try {
      // Get all requests and sort by priority and creation time
      final requests = _queueBox!.values
          .map((e) => QueuedRequest.fromJson(e as Map<String, dynamic>))
          .toList();

      requests.sort((a, b) {
        // Higher priority first
        final priorityCompare = b.priority.compareTo(a.priority);
        if (priorityCompare != 0) return priorityCompare;

        // Older requests first
        return a.createdAt.compareTo(b.createdAt);
      });

      AppLogger.info('[OfflineQueue] 📋 Processing ${requests.length} queued requests...');

      for (final request in requests) {
        await _processRequest(request);

        // Small delay between requests to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (_queueBox!.isEmpty) {
        AppLogger.info('[OfflineQueue] ✅ All queued requests processed successfully!');
      }
    } catch (e) {
      AppLogger.error('[OfflineQueue] Error processing queue: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process a single request
  Future<void> _processRequest(QueuedRequest request) async {
    if (_apiService == null) {
      AppLogger.error('[OfflineQueue] API service not initialized');
      return;
    }

    // Check if max retries exceeded
    if (request.retryCount >= maxRetries) {
      AppLogger.error('[OfflineQueue] ❌ Max retries exceeded for ${request.id.substring(0, 8)}');
      await _queueBox!.delete(request.id);

      // Notify failure
      for (final callback in _onRequestFailed) {
        callback(request, 'Max retries exceeded');
      }
      return;
    }

    // Calculate backoff delay
    if (request.lastAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(request.lastAttempt!);
      final backoffDelay = _calculateBackoff(request.retryCount);

      if (timeSinceLastAttempt < backoffDelay) {
        // Too soon to retry
        return;
      }
    }

    try {
      AppLogger.info(
        '[OfflineQueue] 🔄 Attempting ${request.method} ${request.endpoint} '
        '(attempt ${request.retryCount + 1}/$maxRetries)',
      );

      // Execute request
      final response = await _executeRequest(request);

      if (response.isSuccess) {
        // Success - remove from queue
        await _queueBox!.delete(request.id);
        AppLogger.info('[OfflineQueue] ✅ Request completed: ${request.id.substring(0, 8)}');

        // Notify success
        for (final callback in _onRequestSuccess) {
          callback(request);
        }
      } else {
        // Failed - increment retry count
        final updatedRequest = request.copyWith(
          retryCount: request.retryCount + 1,
          lastAttempt: DateTime.now(),
        );
        await _queueBox!.put(request.id, updatedRequest.toJson());

        AppLogger.warning(
          '[OfflineQueue] ⚠️ Request failed (${response.message}), will retry later',
        );
      }
    } catch (e) {
      // Network error - increment retry count
      final updatedRequest = request.copyWith(
        retryCount: request.retryCount + 1,
        lastAttempt: DateTime.now(),
      );
      await _queueBox!.put(request.id, updatedRequest.toJson());

      AppLogger.warning('[OfflineQueue] ⚠️ Network error: $e, will retry later');
    }
  }

  /// Execute a queued request
  Future<dynamic> _executeRequest(QueuedRequest request) async {
    switch (request.method) {
      case 'GET':
        return await _apiService!.get(
          request.endpoint,
          queryParams: request.queryParams,
        );

      case 'POST':
        return await _apiService!.post(
          request.endpoint,
          body: request.body,
        );

      case 'PUT':
        return await _apiService!.put(
          request.endpoint,
          body: request.body,
        );

      case 'DELETE':
        return await _apiService!.delete(request.endpoint);

      default:
        throw Exception('Unsupported HTTP method: ${request.method}');
    }
  }

  /// Calculate exponential backoff delay
  Duration _calculateBackoff(int retryCount) {
    final delay = initialRetryDelay * (1 << retryCount); // 2^retryCount
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }

  /// Get pending requests count
  int get pendingCount => _queueBox?.length ?? 0;

  /// Get all pending requests
  List<QueuedRequest> get pendingRequests {
    if (_queueBox == null) return [];

    return _queueBox!.values
        .map((e) => QueuedRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Clear all pending requests
  Future<void> clearQueue() async {
    _ensureInitialized();
    await _queueBox!.clear();
    AppLogger.info('[OfflineQueue] 🗑️ Queue cleared');
  }

  /// Remove specific request
  Future<void> removeRequest(String requestId) async {
    _ensureInitialized();
    await _queueBox!.delete(requestId);
    AppLogger.info('[OfflineQueue] 🗑️ Removed request: ${requestId.substring(0, 8)}');
  }

  /// Register callback for when request is queued
  void onRequestQueued(Function(QueuedRequest) callback) {
    _onRequestQueued.add(callback);
  }

  /// Register callback for when request succeeds
  void onRequestSuccess(Function(QueuedRequest) callback) {
    _onRequestSuccess.add(callback);
  }

  /// Register callback for when request fails
  void onRequestFailed(Function(QueuedRequest, String) callback) {
    _onRequestFailed.add(callback);
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception('OfflineQueueService not initialized. Call initialize() first.');
    }
  }

  /// Close service
  Future<void> close() async {
    _retryTimer?.cancel();
    _connectivitySubscription?.cancel();
    await _queueBox?.close();
    _isInitialized = false;
    AppLogger.info('[OfflineQueue] ♦️ Closed');
  }
}
