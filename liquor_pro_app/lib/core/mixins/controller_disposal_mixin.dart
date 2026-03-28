import 'dart:async';
import 'package:flutter/material.dart';

/// Controller Disposal Mixin - Prevents memory leaks
/// Automatically tracks and disposes controllers and subscriptions
///
/// Usage:
/// ```dart
/// class MyScreen extends StatefulWidget {
///   @override
///   State<MyScreen> createState() => _MyScreenState();
/// }
///
/// class _MyScreenState extends State<MyScreen> with ControllerDisposalMixin {
///   late final TextEditingController _nameController;
///   late final AnimationController _animController;
///
///   @override
///   void initState() {
///     super.initState();
///     _nameController = registerTextController(TextEditingController());
///     _animController = registerAnimationController(
///       AnimationController(vsync: this, duration: Duration(seconds: 1)),
///     );
///   }
///
///   @override
///   void dispose() {
///     disposeAll(); // Automatically disposes all registered controllers
///     super.dispose();
///   }
/// }
/// ```
mixin ControllerDisposalMixin<T extends StatefulWidget> on State<T> {
  final List<TextEditingController> _textControllers = [];
  final List<AnimationController> _animationControllers = [];
  final List<ScrollController> _scrollControllers = [];
  final List<TabController> _tabControllers = [];
  final List<FocusNode> _focusNodes = [];
  final List<StreamSubscription> _subscriptions = [];
  final List<void Function()> _customDisposers = [];

  /// Register a TextEditingController for automatic disposal
  T registerTextController<T extends TextEditingController>(T controller) {
    _textControllers.add(controller);
    return controller;
  }

  /// Register an AnimationController for automatic disposal
  T registerAnimationController<T extends AnimationController>(T controller) {
    _animationControllers.add(controller);
    return controller;
  }

  /// Register a ScrollController for automatic disposal
  T registerScrollController<T extends ScrollController>(T controller) {
    _scrollControllers.add(controller);
    return controller;
  }

  /// Register a TabController for automatic disposal
  T registerTabController<T extends TabController>(T controller) {
    _tabControllers.add(controller);
    return controller;
  }

  /// Register a FocusNode for automatic disposal
  T registerFocusNode<T extends FocusNode>(T node) {
    _focusNodes.add(node);
    return node;
  }

  /// Register a StreamSubscription for automatic cancellation
  T registerSubscription<T extends StreamSubscription>(T subscription) {
    _subscriptions.add(subscription);
    return subscription;
  }

  /// Register a custom disposal callback
  void registerDisposer(void Function() disposer) {
    _customDisposers.add(disposer);
  }

  /// Dispose all registered controllers and subscriptions
  void disposeAll() {
    // Dispose text controllers
    for (final controller in _textControllers) {
      controller.dispose();
    }
    _textControllers.clear();

    // Dispose animation controllers
    for (final controller in _animationControllers) {
      controller.dispose();
    }
    _animationControllers.clear();

    // Dispose scroll controllers
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    _scrollControllers.clear();

    // Dispose tab controllers
    for (final controller in _tabControllers) {
      controller.dispose();
    }
    _tabControllers.clear();

    // Dispose focus nodes
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();

    // Cancel subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Run custom disposers
    for (final disposer in _customDisposers) {
      try {
        disposer();
      } catch (e) {
        debugPrint('Error in custom disposer: $e');
      }
    }
    _customDisposers.clear();
  }

  /// Get count of registered resources (for debugging)
  Map<String, int> get resourceCounts => {
    'textControllers': _textControllers.length,
    'animationControllers': _animationControllers.length,
    'scrollControllers': _scrollControllers.length,
    'tabControllers': _tabControllers.length,
    'focusNodes': _focusNodes.length,
    'subscriptions': _subscriptions.length,
    'customDisposers': _customDisposers.length,
  };
}

/// Quick disposal mixin for common text form scenarios
mixin FormDisposalMixin<T extends StatefulWidget> on State<T> {
  final Map<String, TextEditingController> _controllers = {};
  final List<FocusNode> _focusNodes = [];

  /// Create and register a text controller with a key
  TextEditingController controller(String key, {String? initialValue}) {
    if (_controllers.containsKey(key)) {
      return _controllers[key]!;
    }

    final controller = TextEditingController(text: initialValue);
    _controllers[key] = controller;
    return controller;
  }

  /// Create and register a focus node
  FocusNode focusNode() {
    final node = FocusNode();
    _focusNodes.add(node);
    return node;
  }

  /// Get controller by key (throws if not found)
  TextEditingController getController(String key) {
    if (!_controllers.containsKey(key)) {
      throw Exception('Controller with key "$key" not found');
    }
    return _controllers[key]!;
  }

  /// Dispose all form controllers and focus nodes
  void disposeFormControllers() {
    _controllers.forEach((_, controller) => controller.dispose());
    _controllers.clear();

    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }
}
