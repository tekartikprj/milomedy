/// The speed trainer of a loop: the speed changes by a step every few
/// passes, from a speed up (or down) to another, at the frame the loop
/// starts again.
library;

import 'dart:math' as math;

/// A speed trainer: [from] at first, then [step] closer to [to] every
/// [everyPasses] passes of the loop, until [to], where it stays.
class MidiSpeedTrainer {
  /// The speed at first.
  final double from;

  /// The speed reached, then kept.
  final double to;

  /// The change of speed (positive), up or down to [to].
  final double step;

  /// The passes of the loop between two steps, 1 or more.
  final int everyPasses;

  /// A trainer: every speed positive, [step] too, [everyPasses] at least 1
  /// (an [ArgumentError] otherwise).
  MidiSpeedTrainer({
    required this.from,
    required this.to,
    required this.step,
    this.everyPasses = 1,
  }) {
    if (!(from > 0) || !from.isFinite) {
      throw ArgumentError.value(from, 'from', 'must be positive');
    }
    if (!(to > 0) || !to.isFinite) {
      throw ArgumentError.value(to, 'to', 'must be positive');
    }
    if (!(step > 0) || !step.isFinite) {
      throw ArgumentError.value(step, 'step', 'must be positive');
    }
    if (everyPasses < 1) {
      throw ArgumentError.value(
        everyPasses,
        'everyPasses',
        'must be 1 or more',
      );
    }
  }

  /// The speed after [passes] passes of the loop.
  double speedAfter(int passes) {
    var change = (passes ~/ everyPasses) * step;
    return to >= from
        ? math.min(to, from + change)
        : math.max(to, from - change);
  }

  /// The trainer of [map] (from [toMap]).
  factory MidiSpeedTrainer.fromMap(Map<Object?, Object?> map) =>
      MidiSpeedTrainer(
        from: (map['from'] as num).toDouble(),
        to: (map['to'] as num).toDouble(),
        step: (map['step'] as num).toDouble(),
        everyPasses: (map['everyPasses'] as num?)?.toInt() ?? 1,
      );

  /// As a map.
  Map<String, Object?> toMap() => {
    'from': from,
    'to': to,
    'step': step,
    'everyPasses': everyPasses,
  };

  @override
  bool operator ==(Object other) =>
      other is MidiSpeedTrainer &&
      other.from == from &&
      other.to == to &&
      other.step == step &&
      other.everyPasses == everyPasses;

  @override
  int get hashCode => Object.hash(from, to, step, everyPasses);

  @override
  String toString() =>
      'MidiSpeedTrainer($from to $to by $step every $everyPasses passes)';
}
