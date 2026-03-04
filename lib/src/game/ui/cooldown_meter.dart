import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_assets.dart';

class CooldownMeter extends StatefulWidget {
  const CooldownMeter({
    required this.label,
    required this.remaining,
    required this.total,
    required this.activeColor,
    required this.isPlayerSide,
    required this.timeLabel,
    required this.readyToFlash,
    required this.flashTint,
    required this.flashDuration,
    super.key,
  });

  final String label;
  final Duration remaining;
  final Duration total;
  final Color activeColor;
  final bool isPlayerSide;
  final String timeLabel;
  final bool readyToFlash;
  final Color flashTint;
  final Duration flashDuration;

  @override
  State<CooldownMeter> createState() => _CooldownMeterState();
}

class _CooldownMeterState extends State<CooldownMeter>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Ticker _depletionTicker;
  Duration _remainingSnapshot = Duration.zero;
  DateTime _remainingSampledAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _remainingSnapshot = widget.remaining;
    _remainingSampledAt = DateTime.now();
    _pulse = AnimationController(vsync: this, duration: widget.flashDuration);
    _depletionTicker = createTicker((_) {
      if (!mounted) {
        return;
      }
      if (_effectiveRemaining().inMilliseconds <= 0) {
        _depletionTicker.stop();
      }
      setState(() {});
    });
    _syncPulse();
    _syncDepletionTicker();
  }

  @override
  void didUpdateWidget(covariant CooldownMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remaining != widget.remaining) {
      _remainingSnapshot = widget.remaining;
      _remainingSampledAt = DateTime.now();
    }
    if (oldWidget.flashDuration != widget.flashDuration) {
      _pulse.duration = widget.flashDuration;
    }
    _syncPulse();
    _syncDepletionTicker();
  }

  void _syncPulse() {
    if (widget.readyToFlash) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
      return;
    }
    if (_pulse.isAnimating) {
      _pulse.stop();
    }
    _pulse.value = 0;
  }

  void _syncDepletionTicker() {
    if (_effectiveRemaining().inMilliseconds <= 0) {
      if (_depletionTicker.isActive) {
        _depletionTicker.stop();
      }
      return;
    }
    if (!_depletionTicker.isActive) {
      _depletionTicker.start();
    }
  }

  Duration _effectiveRemaining() {
    if (_remainingSnapshot.inMilliseconds <= 0) {
      return Duration.zero;
    }
    final elapsed = DateTime.now().difference(_remainingSampledAt);
    final remaining = _remainingSnapshot - elapsed;
    if (remaining.inMilliseconds <= 0) {
      return Duration.zero;
    }
    return remaining;
  }

  double _effectiveRatio() {
    final totalMs = widget.total.inMilliseconds;
    if (totalMs <= 0) {
      return 0;
    }
    final ratio = _effectiveRemaining().inMilliseconds / totalMs;
    return ratio.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _depletionTicker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clampedRatio = _effectiveRatio();

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = widget.readyToFlash ? (0.2 + (0.8 * _pulse.value)) : 0.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: widget.flashTint.withValues(alpha: 0.22 * glow),
                blurRadius: 12 + (22 * glow),
                spreadRadius: 0.5 + (3.5 * glow),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // "Spent" portion remains visible as a muted bar for readability.
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0.7,
                    0,
                  ]),
                  child: Image.asset(
                    AppAssets.horizontalTimeBar,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                if (clampedRatio > 0)
                  ClipRect(
                    clipper: _HorizontalProgressClipper(clampedRatio),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        widget.activeColor.withValues(alpha: 0.22),
                        BlendMode.hardLight,
                      ),
                      child: Image.asset(
                        AppAssets.horizontalTimeBar,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                if (widget.readyToFlash)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        // Strong pulse for "ready" so players catch it instantly.
                        decoration: BoxDecoration(
                          color: widget.flashTint.withValues(
                            alpha: 0.24 + (0.6 * _pulse.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.25,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.96),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        if (widget.isPlayerSide) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.person,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.96),
                            shadows: const <Shadow>[
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                        Text(
                          widget.timeLabel,
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.96),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HorizontalProgressClipper extends CustomClipper<Rect> {
  const _HorizontalProgressClipper(this.progressRatio);

  final double progressRatio;

  @override
  Rect getClip(Size size) {
    final clamped = progressRatio.clamp(0.0, 1.0);
    return Rect.fromLTWH(0, 0, size.width * clamped, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalProgressClipper oldClipper) {
    return oldClipper.progressRatio != progressRatio;
  }
}
