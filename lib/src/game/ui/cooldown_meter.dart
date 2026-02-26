import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    final ready = clampedRatio == 0.0;
    final fillColor = ready ? const Color(0xFF2ECC71) : widget.activeColor;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = widget.readyToFlash ? (0.2 + (0.8 * _pulse.value)) : 0.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD5DEE8), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: widget.flashTint.withValues(alpha: 0.2 * glow),
                blurRadius: 8 + (18 * glow),
                spreadRadius: 0.4 + (2.8 * glow),
              ),
            ],
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFDFEFE), Color(0xFFF4F7FA)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11.5),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFEBF1F7), Color(0xFFDCE5EF)],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: clampedRatio,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  fillColor.withValues(alpha: 0.72),
                                  fillColor.withValues(alpha: 0.98),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.readyToFlash)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      // Stronger pulse for "cooldown ready" so it reads instantly.
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: widget.flashTint.withValues(
                          alpha: 0.26 + (0.62 * _pulse.value),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          fontSize: 12,
                          color: Color(0xFF1F2933),
                        ),
                      ),
                      if (widget.isPlayerSide) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.person,
                          size: 12,
                          color: Color(0xFF334155),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        widget.timeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF1F2933),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
