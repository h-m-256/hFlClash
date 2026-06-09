import 'package:flutter/foundation.dart';

class DelayTestProgress {
  final int completed;
  final int total;
  final bool cancelled;

  const DelayTestProgress({
    required this.completed,
    required this.total,
    this.cancelled = false,
  });

  double get value => total <= 0 ? 0 : completed.clamp(0, total) / total;

  DelayTestProgress copyWith({int? completed, int? total, bool? cancelled}) {
    return DelayTestProgress(
      completed: completed ?? this.completed,
      total: total ?? this.total,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

class ProgressMessageState {
  final String id;
  final String title;
  final ValueListenable<DelayTestProgress> progress;
  final VoidCallback onCancel;

  const ProgressMessageState({
    required this.id,
    required this.title,
    required this.progress,
    required this.onCancel,
  });
}
