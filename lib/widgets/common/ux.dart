import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Small collection of helpers and widgets for micro-interactions:
/// - haptic feedback helpers
/// - simple scale-on-tap button
/// - small loading / success widgets

enum HapticType { light, medium, heavy, selection, success, error }

class Haptics {
  static Future<void> light() async => HapticFeedback.lightImpact();
  static Future<void> medium() async => HapticFeedback.mediumImpact();
  static Future<void> heavy() async => HapticFeedback.heavyImpact();
  static Future<void> selection() async => HapticFeedback.selectionClick();

  /// Simple success vibration composed from a couple of impacts
  static Future<void> success() async {
    try {
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 40));
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  static Future<void> error() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}

/// InteractiveScaleButton: wraps a widget and gives a subtle scale animation
/// and optional haptic feedback when tapped.
class InteractiveScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Duration duration;
  final double downScale;
  final bool enabled;

  const InteractiveScaleButton({
    super.key,
    required this.child,
    required this.onTap,
    this.duration = const Duration(milliseconds: 120),
    this.downScale = 0.96,
    this.enabled = true,
  });

  @override
  State<InteractiveScaleButton> createState() => _InteractiveScaleButtonState();
}

class _InteractiveScaleButtonState extends State<InteractiveScaleButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    setState(() => _scale = widget.downScale);
  }

  void _onTapUp(TapUpDetails _) async {
    if (!widget.enabled) return;
    setState(() => _scale = 1.0);
    // small delay to allow the scale-up animation to show
    await Future.delayed(const Duration(milliseconds: 30));
    widget.onTap?.call();
  }

  void _onTapCancel() {
    if (!widget.enabled) return;
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: widget.enabled ? _onTapDown : null,
      onTapUp: widget.enabled ? _onTapUp : null,
      onTapCancel: widget.enabled ? _onTapCancel : null,
      child: AnimatedScale(
        scale: _scale,
        duration: widget.duration,
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Small centered loading indicator you can drop anywhere
class LoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  const LoadingIndicator({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Simple success animation (scale + fade) with a check icon.
class SuccessCheckAnimation extends StatefulWidget {
  final double size;
  final Color? color;
  final Duration duration;
  final VoidCallback? onCompleted;

  const SuccessCheckAnimation({
    super.key,
    this.size = 72,
    this.color,
    this.duration = const Duration(milliseconds: 600),
    this.onCompleted,
  });

  @override
  State<SuccessCheckAnimation> createState() => _SuccessCheckAnimationState();
}

class _SuccessCheckAnimationState extends State<SuccessCheckAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onCompleted?.call();
    });

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.secondary;
    return FadeTransition(
      opacity: _ctrl.drive(CurveTween(curve: Curves.easeOut)),
      child: ScaleTransition(
        scale: _ctrl.drive(Tween(begin: 0.6, end: 1.0).chain(CurveTween(curve: Curves.elasticOut))),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.12),
          ),
          child: Center(
            child: Icon(Icons.check_circle_rounded, color: color, size: widget.size * 0.58),
          ),
        ),
      ),
    );
  }
}

/// Show an animated dialog with slide + fade effect
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = Colors.black54,
  Duration duration = const Duration(milliseconds: 300),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: duration,
    pageBuilder: (ctx, a1, a2) => SafeArea(child: builder(ctx)),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
