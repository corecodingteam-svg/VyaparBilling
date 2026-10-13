import 'package:flutter/material.dart';

import '../theme.dart';

/// An indeterminate progress bar: a multicolour band that glides along a soft track. Use it instead of
/// `LinearProgressIndicator()` wherever the length of the wait is unknown (start-up, scanning, long jobs).
/// With "reduce motion" on it is a still gradient.
class GradientProgressBar extends StatefulWidget {
  const GradientProgressBar({super.key, this.height = 3});
  final double height;

  @override
  State<GradientProgressBar> createState() => _GradientProgressBarState();
}

class _GradientProgressBarState extends State<GradientProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !reduceMotion(context);
    if (animate && !_running) {
      _controller.repeat();
      _running = true;
    } else if (!animate && _running) {
      _controller.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.border),
              child: LayoutBuilder(
                builder: (context, c) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final band = c.maxWidth * 0.4;
                    // Starts fully off the left edge and leaves fully off the right.
                    final x = _running ? -band + (c.maxWidth + band) * Curves.easeInOut.transform(_controller.value) : (c.maxWidth - band) / 2;
                    return Stack(children: [
                      Positioned(
                        left: x,
                        width: band,
                        top: 0,
                        bottom: 0,
                        child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: AppColors.loaderGradient))),
                      ),
                    ]);
                  },
                ),
              ),
            ),
          ),
        ),
      );
}
