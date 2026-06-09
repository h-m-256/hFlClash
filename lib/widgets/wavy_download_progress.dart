import 'dart:math' as math;

import 'package:flutter/material.dart';

class WavyDownloadProgress extends StatefulWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color waveColor;
  final Color trackColor;
  final double waveAmplitude;
  final double waveLength;
  final Widget? child;

  const WavyDownloadProgress({
    super.key,
    required this.progress,
    this.size = 56,
    this.strokeWidth = 5,
    required this.color,
    required this.waveColor,
    required this.trackColor,
    this.waveAmplitude = 2,
    this.waveLength = 14,
    this.child,
  });

  @override
  State<WavyDownloadProgress> createState() => _WavyDownloadProgressState();
}

class _WavyDownloadProgressState extends State<WavyDownloadProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          return CustomPaint(
            painter: _WavyDownloadProgressPainter(
              progress: widget.progress.clamp(0, 1),
              strokeWidth: widget.strokeWidth,
              color: widget.color,
              waveColor: widget.waveColor,
              trackColor: widget.trackColor,
              waveAmplitude: widget.waveAmplitude,
              waveLength: widget.waveLength,
              phase: _controller.value * math.pi * 2,
            ),
            child: child,
          );
        },
        child: Center(child: widget.child),
      ),
    );
  }
}

class _WavyDownloadProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final Color waveColor;
  final Color trackColor;
  final double waveAmplitude;
  final double waveLength;
  final double phase;

  const _WavyDownloadProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.waveColor,
    required this.trackColor,
    required this.waveAmplitude,
    required this.waveLength,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    const startAngle = -math.pi / 2;
    final sweepAngle = progress * math.pi * 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (sweepAngle <= 0) return;

    final wavePaint = Paint()
      ..color = Color.alphaBlend(waveColor, color)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;
    final path = Path();
    final safeWaveLength = math.max(1.0, waveLength);
    final points = math.min(
      220,
      math.max(16, (radius * sweepAngle / 2).ceil()),
    );
    for (var i = 0; i <= points; i++) {
      final t = i / points;
      final angle = startAngle + sweepAngle * t;
      final distance = radius * sweepAngle * t;
      final localRadius =
          radius +
          math.sin(distance / safeWaveLength * math.pi * 2 + phase) *
              waveAmplitude;
      final point = Offset(
        center.dx + math.cos(angle) * localRadius,
        center.dy + math.sin(angle) * localRadius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _WavyDownloadProgressPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        strokeWidth != oldDelegate.strokeWidth ||
        color != oldDelegate.color ||
        waveColor != oldDelegate.waveColor ||
        trackColor != oldDelegate.trackColor ||
        waveAmplitude != oldDelegate.waveAmplitude ||
        waveLength != oldDelegate.waveLength ||
        phase != oldDelegate.phase;
  }
}

class WavyDownloadProgressExample extends StatelessWidget {
  const WavyDownloadProgressExample({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return WavyDownloadProgress(
      progress: 0.84,
      size: 72,
      strokeWidth: 6,
      color: colorScheme.primary,
      waveColor: colorScheme.primary,
      trackColor: colorScheme.surfaceContainerHighest,
      waveAmplitude: 2.5,
      waveLength: 14,
      child: Icon(Icons.apps, color: colorScheme.primary),
    );
  }
}
