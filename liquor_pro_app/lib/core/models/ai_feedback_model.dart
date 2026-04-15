import 'dart:convert';

enum AIFlowType {
  stockSetup,
  dailySales,
  purchaseEntry;

  String get key {
    switch (this) {
      case AIFlowType.stockSetup:
        return 'stock_setup';
      case AIFlowType.dailySales:
        return 'daily_sales';
      case AIFlowType.purchaseEntry:
        return 'purchase_entry';
    }
  }

  String get title {
    switch (this) {
      case AIFlowType.stockSetup:
        return 'AI Stock Setup Complete!';
      case AIFlowType.dailySales:
        return 'Daily Sales Submitted!';
      case AIFlowType.purchaseEntry:
        return 'Purchase Entry Complete!';
    }
  }

  /// Feedback tags specific to each flow type
  List<String> get specificTags {
    switch (this) {
      case AIFlowType.stockSetup:
        return ['Correct quantities', 'Wrong items', 'Missing items'];
      case AIFlowType.dailySales:
        return ['Matched receipts', 'Needs improvement', 'Missing items'];
      case AIFlowType.purchaseEntry:
        return ['Correct prices', 'Wrong items', 'Needs improvement'];
    }
  }
}

class AIFeedbackEntry {
  final String id;
  final String flowType;
  final int rating;
  final List<String> tags;
  final String? comment;
  final DateTime timestamp;

  const AIFeedbackEntry({
    required this.id,
    required this.flowType,
    required this.rating,
    required this.tags,
    this.comment,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'flow_type': flowType,
        'rating': rating,
        'tags': tags,
        'comment': comment,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AIFeedbackEntry.fromJson(Map<String, dynamic> json) {
    return AIFeedbackEntry(
      id: json['id'] as String,
      flowType: json['flow_type'] as String,
      rating: json['rating'] as int,
      tags: List<String>.from(json['tags'] as List),
      comment: json['comment'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory AIFeedbackEntry.fromJsonString(String jsonString) {
    return AIFeedbackEntry.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
