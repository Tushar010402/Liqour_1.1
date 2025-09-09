import 'package:flutter/material.dart';

class PremiumPageTransitions {
  static PageTransitionsBuilder get theme => const PremiumPageTransitionsBuilder();
}

class PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T extends Object?>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Different transitions based on platform and route settings
    return _buildSlideTransition(
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }

  Widget _buildSlideTransition({
    required BuildContext context,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      )),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.3, 0.0),
        ).animate(CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeInOutCubic,
        )),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }
}

class CustomPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final PageTransitionType transitionType;
  final Duration duration;

  CustomPageRoute({
    required this.child,
    this.transitionType = PageTransitionType.slideRight,
    this.duration = const Duration(milliseconds: 300),
    super.settings,
  }) : super(
          pageBuilder: (context, animation, _) => child,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    switch (transitionType) {
      case PageTransitionType.slideRight:
        return _slideTransition(animation, child, const Offset(1.0, 0.0));
      case PageTransitionType.slideLeft:
        return _slideTransition(animation, child, const Offset(-1.0, 0.0));
      case PageTransitionType.slideUp:
        return _slideTransition(animation, child, const Offset(0.0, 1.0));
      case PageTransitionType.slideDown:
        return _slideTransition(animation, child, const Offset(0.0, -1.0));
      case PageTransitionType.fade:
        return _fadeTransition(animation, child);
      case PageTransitionType.scale:
        return _scaleTransition(animation, child);
      case PageTransitionType.rotation:
        return _rotationTransition(animation, child);
      case PageTransitionType.size:
        return _sizeTransition(animation, child);
    }
  }

  Widget _slideTransition(
    Animation<double> animation,
    Widget child,
    Offset begin,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: begin,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      )),
      child: child,
    );
  }

  Widget _fadeTransition(Animation<double> animation, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      ),
      child: child,
    );
  }

  Widget _scaleTransition(Animation<double> animation, Widget child) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.8,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutBack,
      )),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }

  Widget _rotationTransition(Animation<double> animation, Widget child) {
    return RotationTransition(
      turns: Tween<double>(
        begin: 0.8,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      )),
      child: ScaleTransition(
        scale: animation,
        child: child,
      ),
    );
  }

  Widget _sizeTransition(Animation<double> animation, Widget child) {
    return Align(
      alignment: Alignment.center,
      child: SizeTransition(
        sizeFactor: CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ),
        child: child,
      ),
    );
  }
}

enum PageTransitionType {
  slideRight,
  slideLeft,
  slideUp,
  slideDown,
  fade,
  scale,
  rotation,
  size,
}

// Hero Animation Extensions
extension HeroAnimationExtensions on Widget {
  Widget withHeroAnimation(String tag, {Duration duration = const Duration(milliseconds: 300)}) {
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOutBack),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: this,
          ),
        );
      },
      child: this,
    );
  }
}

// Shared Element Transition
class SharedElementTransition extends StatelessWidget {
  final String tag;
  final Widget child;
  final Duration duration;

  const SharedElementTransition({
    super.key,
    required this.tag,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Transform.scale(
              scale: Tween<double>(
                begin: direction == HeroFlightDirection.push ? 0.9 : 1.1,
                end: 1.0,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutQuart,
              )).value,
              child: Material(
                type: MaterialType.transparency,
                child: this.child,
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}