import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';
import '../theme.dart';

/// Whether this device asks for less motion; when it does, nothing in this file animates.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------- shimmer and skeletons

/// Sweeps a soft highlight across its child, used on skeleton shapes while content loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.shimmer);
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !reduceMotion(context);
    if (animate && !_running) {
      _controller.repeat();
    } else if (!animate && _running) {
      _controller.stop();
    }
    _running = animate;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // The highlight travels from left of the shape to right of it.
          final slide = _controller.value * 3 - 1;
          return LinearGradient(
            begin: Alignment(slide - 1, 0),
            end: Alignment(slide, 0),
            colors: const [AppColors.border, AppColors.surfaceMuted, AppColors.border],
            stops: const [0.2, 0.5, 0.8],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

/// A rounded placeholder shape. Put several inside one [Shimmer] so they sweep together.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = AppIconSize.xs, this.radius = AppRadius.sm, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surface, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(radius)),
  );
}

/// What a list of rows looks like before its data arrives: an avatar, two lines of text and a figure on the right.
/// Shows as many rows as fit the space it is given.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.maxRows = 8, this.leading = true});
  final int maxRows;
  final bool leading;

  static const _rowHeight = 64.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final fit = c.hasBoundedHeight ? (c.maxHeight / _rowHeight).floor() : maxRows;
      final rows = fit.clamp(2, maxRows);
      return Shimmer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                child: Row(
                  children: [
                    if (leading) ...[const SkeletonBox(height: 36, circle: true), const SizedBox(width: AppSpace.md)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 120.0 + (i % 3) * 40, height: AppFont.bodyLarge),
                          const SizedBox(height: AppSpace.sm),
                          SkeletonBox(width: 200.0 + (i % 2) * 60, height: AppFont.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    const SkeletonBox(width: 64, height: AppFont.bodyLarge),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// A table before its data arrives: a header and rows of cells.
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({super.key, this.rows = 6, this.columns = 4});
  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        Container(
          height: AppSize.control,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          alignment: Alignment.centerLeft,
          color: AppColors.surfaceMuted,
          child: Row(children: [for (var c = 0; c < columns; c++) ...[if (c > 0) const SizedBox(width: AppSpace.xxl), const Expanded(child: SkeletonBox(height: AppFont.caption))]]),
        ),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md + 2),
            child: Row(children: [for (var c = 0; c < columns; c++) ...[if (c > 0) const SizedBox(width: AppSpace.xxl), Expanded(flex: c == 0 ? 2 : 1, child: SkeletonBox(height: AppFont.body))]]),
          ),
      ],
    ),
  );
}

/// A summary tile before its figure arrives.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(AppSpace.lg),
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SkeletonBox(width: 90, height: AppFont.small), SizedBox(height: AppSpace.md), SkeletonBox(width: 140, height: AppFont.headline)],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- entrances and crossfades

/// Fades a child in while it rises a few pixels. With [index] the entrance is delayed a little for each row (up to
/// [AppMotion.staggerMax]) so a list appears in a quick cascade instead of all at once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, this.index = 0, required this.child});
  final int index;
  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.stagger * math.min(widget.index, AppMotion.staggerMax);
    final total = AppMotion.normal + delay;
    _controller = AnimationController(vsync: this, duration: total);
    // The wait is part of the one animation (no timers), so it ends cleanly in tests and when the screen is closed.
    _curve = CurvedAnimation(parent: _controller, curve: Interval(delay.inMilliseconds / total.inMilliseconds, 1, curve: AppMotion.curve));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve), child: widget.child),
    );
  }
}

/// Crossfades between states (loading, content, empty, error) when the child's [key] changes.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: reduceMotion(context) ? Duration.zero : AppMotion.normal,
    switchInCurve: AppMotion.curve,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
    child: child,
  );
}

/// Shows or hides [child] by growing and shrinking it, so a group of rows that opens pushes the rest down smoothly.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.open, required this.child});
  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: reduceMotion(context) ? Duration.zero : AppMotion.normal,
    curve: AppMotion.curve,
    alignment: Alignment.topCenter,
    child: open ? child : const SizedBox(width: double.infinity),
  );
}
