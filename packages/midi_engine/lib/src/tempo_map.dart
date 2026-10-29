/// The tempo map of a song: ticks to seconds and back, with every tempo
/// change; or a fixed number of ticks per second (an SMPTE division).
library;

/// The default tempo, 120 bpm, in microseconds per quarter note.
const midiDefaultMicrosPerQuarter = 500000;

/// A tempo change.
class MidiTempo {
  /// The tick it starts at.
  final int tick;

  /// The length of a quarter note, in microseconds.
  final int microsPerQuarter;

  /// A tempo.
  const MidiTempo(this.tick, this.microsPerQuarter);

  /// The quarter notes per minute.
  double get bpm => 60000000 / microsPerQuarter;

  @override
  String toString() => 'MidiTempo($tick, ${bpm.toStringAsFixed(2)} bpm)';
}

/// Converts ticks to seconds and back.
class MidiTempoMap {
  /// The ticks per quarter note, null with an SMPTE division.
  final int? ppq;

  /// The ticks per second of an SMPTE division, null otherwise.
  final double? ticksPerSecond;

  /// The tempo changes, by tick, the first one at tick 0 (empty with an SMPTE
  /// division).
  final List<MidiTempo> tempos;

  /// The seconds at the tick of each tempo.
  final List<double> _seconds;

  MidiTempoMap._(this.ppq, this.ticksPerSecond, this.tempos, this._seconds);

  /// The map of [tempos] with [ppq] ticks per quarter note: 120 bpm until the
  /// first one, the last one wins at the same tick.
  factory MidiTempoMap({
    required int ppq,
    Iterable<MidiTempo> tempos = const [],
  }) {
    if (ppq <= 0) {
      throw ArgumentError.value(ppq, 'ppq', 'must be positive');
    }
    var sorted = tempos.toList()..sort((a, b) => a.tick.compareTo(b.tick));
    var kept = <MidiTempo>[const MidiTempo(0, midiDefaultMicrosPerQuarter)];
    for (var tempo in sorted) {
      if (tempo.tick <= kept.last.tick) {
        kept.last = MidiTempo(kept.last.tick, tempo.microsPerQuarter);
      } else {
        kept.add(tempo);
      }
    }
    var seconds = <double>[0];
    for (var i = 1; i < kept.length; i++) {
      var previous = kept[i - 1];
      seconds.add(
        seconds.last +
            (kept[i].tick - previous.tick) *
                previous.microsPerQuarter /
                (1e6 * ppq),
      );
    }
    return MidiTempoMap._(ppq, null, List.unmodifiable(kept), seconds);
  }

  /// A fixed [ticksPerSecond] (an SMPTE division): the tempo is ignored.
  MidiTempoMap.smpte(double ticksPerSecond)
    : this._(null, ticksPerSecond, const [], const []);

  /// True with an SMPTE division.
  bool get isSmpte => ticksPerSecond != null;

  /// The index of the tempo at [tick].
  int _indexAt(num tick) {
    var low = 0;
    var high = tempos.length - 1;
    while (low < high) {
      var mid = (low + high + 1) >> 1;
      if (tempos[mid].tick <= tick) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// The seconds of [tick].
  double secondsOf(num tick) {
    var ticksPerSecond = this.ticksPerSecond;
    if (ticksPerSecond != null) {
      return tick / ticksPerSecond;
    }
    var index = _indexAt(tick);
    var tempo = tempos[index];
    return _seconds[index] +
        (tick - tempo.tick) * tempo.microsPerQuarter / (1e6 * ppq!);
  }

  /// The tick at [seconds], with its fraction.
  double tickAt(double seconds) {
    var ticksPerSecond = this.ticksPerSecond;
    if (ticksPerSecond != null) {
      return seconds * ticksPerSecond;
    }
    var low = 0;
    var high = tempos.length - 1;
    while (low < high) {
      var mid = (low + high + 1) >> 1;
      if (_seconds[mid] <= seconds) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    var tempo = tempos[low];
    return tempo.tick +
        (seconds - _seconds[low]) * 1e6 * ppq! / tempo.microsPerQuarter;
  }

  /// The tempo at [tick] (120 bpm with an SMPTE division).
  MidiTempo tempoAt(num tick) => isSmpte
      ? const MidiTempo(0, midiDefaultMicrosPerQuarter)
      : tempos[_indexAt(tick)];
}
