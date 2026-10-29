/// The reeds of an accordion (from accordelio): each note sounds one or more
/// reeds (ranks), a band limited wave read from a table, with a short attack
/// and release, as free reeds speak.
///
/// The treble plays the ranks of its register (16' bassoon, 8' clarinet,
/// the 8' tuned sharp and flat of the musette, 4' piccolo); a bass sounds
/// its note and the octave below; a chord sounds one rank.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_synth.dart';
import 'midi_synth.dart';

/// A rank of reeds: its octave (-1 for 16', 0 for 8', 1 for 4') and its
/// tuning in cents (the musette reeds, sharp or flat).
class ReedRank {
  /// The octave.
  final int octave;

  /// The tuning, in cents.
  final double cents;

  /// A rank.
  const ReedRank(this.octave, [this.cents = 0]);
}

/// A register of the treble: the ranks it opens.
class ReedRegister {
  /// The id (`clarinet`, `musette`).
  final String id;

  /// The ranks.
  final List<ReedRank> ranks;

  /// A register.
  const ReedRegister(this.id, this.ranks);

  /// The number of 8' ranks (the dots in the middle of its symbol).
  int get middleRanks => ranks.where((rank) => rank.octave == 0).length;

  /// True with a 16' rank (the dot at the bottom of its symbol).
  bool get hasLow => ranks.any((rank) => rank.octave < 0);

  /// True with a 4' rank (the dot at the top of its symbol).
  bool get hasHigh => ranks.any((rank) => rank.octave > 0);

  /// The register of [id], the clarinet when unknown.
  static ReedRegister byId(String? id) =>
      reedRegisters.where((register) => register.id == id).firstOrNull ??
      reedRegisters.first;
}

/// The musette detune: the third reed 5 Hz off at A4 (435, 440, 445 Hz,
/// the modern French musette), about 20 cents.
const reedMusetteCents = 19.6;

/// The registers of the treble of a four rank (LMMH) accordion, and the
/// musette of a three middle rank one.
const reedRegisters = <ReedRegister>[
  ReedRegister('clarinet', [ReedRank(0)]),
  ReedRegister('bassoon', [ReedRank(-1)]),
  ReedRegister('piccolo', [ReedRank(1)]),
  ReedRegister('violin', [ReedRank(0), ReedRank(0, 9)]),
  ReedRegister('musette', [
    ReedRank(0),
    ReedRank(0, reedMusetteCents),
    ReedRank(0, -reedMusetteCents),
  ]),
  ReedRegister('bandoneon', [ReedRank(-1), ReedRank(0)]),
  ReedRegister('oboe', [ReedRank(0), ReedRank(1)]),
  ReedRegister('master', [
    ReedRank(-1),
    ReedRank(0),
    ReedRank(0, 12),
    ReedRank(1),
  ]),
];

/// The color of a reed wave: how the harmonics fall.
enum ReedTimbre {
  /// The treble: odd harmonics stronger (the clarinet tone).
  treble,

  /// The basses: bright, buzzy.
  bass,

  /// The chords: softer.
  chord,
}

/// The wave tables of a timbre, one per octave of the played frequency,
/// each with the harmonics that stay below 18 kHz at the top of its octave
/// (no aliasing), made when first needed and shared.
class ReedWaveTables {
  /// The samples of a table (a guard sample is added).
  static const size = 2048;

  static final _byTimbre = <ReedTimbre, ReedWaveTables>{};

  /// The timbre.
  final ReedTimbre timbre;

  final _tables = <int, Float64List>{};

  ReedWaveTables._(this.timbre);

  /// The tables of [timbre].
  factory ReedWaveTables.of(ReedTimbre timbre) =>
      _byTimbre.putIfAbsent(timbre, () => ReedWaveTables._(timbre));

  /// The octave index of [frequency]: 0 up to 32 Hz, 1 up to 64 Hz...
  static int octaveOf(double frequency) {
    var octave = 0;
    var top = 32.0;
    while (frequency > top && octave < 12) {
      top *= 2;
      octave++;
    }
    return octave;
  }

  /// The table for [frequency].
  Float64List tableFor(double frequency) {
    var octave = octaveOf(frequency);
    return _tables.putIfAbsent(octave, () => _build(octave));
  }

  double _amplitude(int harmonic) {
    var n = harmonic.toDouble();
    switch (timbre) {
      case ReedTimbre.treble:
        return (harmonic.isOdd ? 1.0 : 0.5) / math.pow(n, 1.05);
      case ReedTimbre.bass:
        return (harmonic.isOdd ? 1.0 : 0.8) / math.pow(n, 0.85);
      case ReedTimbre.chord:
        return (harmonic.isOdd ? 1.0 : 0.6) / math.pow(n, 1.35);
    }
  }

  Float64List _build(int octave) {
    var top = 32.0 * math.pow(2, octave);
    var harmonics = (18000 / top).floor().clamp(1, 160);
    var table = Float64List(size + 1);
    var step = 2 * math.pi / size;
    for (var h = 1; h <= harmonics; h++) {
      var amplitude = _amplitude(h);
      // sin(h·x) by rotation, x stepping by `step`.
      var c = math.cos(h * step);
      var s = math.sin(h * step);
      var sin = 0.0;
      var cos = 1.0;
      for (var i = 0; i < size; i++) {
        table[i] += amplitude * sin;
        var nextSin = sin * c + cos * s;
        cos = cos * c - sin * s;
        sin = nextSin;
      }
    }
    var peak = 0.0;
    for (var i = 0; i < size; i++) {
      var value = table[i].abs();
      if (value > peak) {
        peak = value;
      }
    }
    for (var i = 0; i < size; i++) {
      table[i] /= peak;
    }
    table[size] = table[0];
    return table;
  }
}

/// A reed instrument: its timbre, its ranks, its loudness and envelope.
class ReedInstrument implements DartInstrument {
  /// The timbre.
  final ReedTimbre timbre;

  /// The ranks each note sounds (a new register is heard from the next
  /// notes).
  List<ReedRank> ranks;

  /// The loudness of a note at full velocity, shared by its ranks.
  final double gain;

  /// The attack, in seconds.
  final double attack;

  /// The release, in seconds.
  final double release;

  /// An instrument.
  ReedInstrument({
    required this.timbre,
    required this.ranks,
    required this.gain,
    required this.attack,
    required this.release,
  });

  /// The treble, with the ranks of [register] (the clarinet by default).
  ReedInstrument.treble({ReedRegister? register})
    : this(
        timbre: ReedTimbre.treble,
        ranks: (register ?? reedRegisters.first).ranks,
        gain: 0.22,
        attack: 0.014,
        release: 0.045,
      );

  /// The basses: the note and the octave below.
  ReedInstrument.bass()
    : this(
        timbre: ReedTimbre.bass,
        ranks: const [ReedRank(0), ReedRank(-1, 2)],
        gain: 0.2 * math.sqrt2,
        attack: 0.02,
        release: 0.06,
      );

  /// The chords: one rank.
  ReedInstrument.chord()
    : this(
        timbre: ReedTimbre.chord,
        ranks: const [ReedRank(0)],
        gain: 0.13,
        attack: 0.016,
        release: 0.04,
      );

  /// Sets the ranks of [register].
  set register(ReedRegister register) => ranks = register.ranks;

  @override
  DartVoice voice(int key, double velocity, int sampleRate) {
    var tables = ReedWaveTables.of(timbre);
    var frequencies = [
      for (var rank in ranks)
        midiKeyFrequency(key + 12 * rank.octave, cents: rank.cents),
    ];
    return _ReedVoice(
      [for (var frequency in frequencies) tables.tableFor(frequency)],
      [for (var frequency in frequencies) frequency / sampleRate],
      gain * velocity / math.sqrt(ranks.length),
      math.max(1, (attack * sampleRate).round()),
      math.max(1, (release * sampleRate).round()),
    );
  }
}

class _ReedVoice implements DartVoice {
  final List<Float64List> _tables;
  final Float64List _phases;
  final Float64List _increments;
  final double _gain;
  final double _attackStep;
  final double _releaseStep;
  var _level = 0.0;
  var _released = false;

  _ReedVoice(
    this._tables,
    List<double> increments,
    this._gain,
    int attackFrames,
    int releaseFrames,
  ) : _phases = Float64List(increments.length),
      _increments = Float64List.fromList(increments),
      _attackStep = 1 / attackFrames,
      _releaseStep = 1 / releaseFrames {
    // Reeds do not start in phase.
    for (var i = 0; i < _phases.length; i++) {
      _phases[i] = ((i + 1) * 0.37) % 1;
    }
  }

  @override
  bool get ended => _released && _level <= 0;

  @override
  void release() => _released = true;

  @override
  void render(Float32List out, int start, int count, double gain) {
    var level = _level;
    var ranks = _tables.length;
    var voiceGain = _gain * gain;
    const size = ReedWaveTables.size;
    for (var i = start; i < start + count; i++) {
      if (!_released) {
        if (level < 1) {
          level += _attackStep;
          if (level > 1) {
            level = 1;
          }
        }
      } else {
        level -= _releaseStep;
        if (level <= 0) {
          level = 0;
          break;
        }
      }
      var sample = 0.0;
      for (var r = 0; r < ranks; r++) {
        var table = _tables[r];
        var position = _phases[r] * size;
        var index = position.toInt();
        var fraction = position - index;
        var a = table[index];
        sample += a + (table[index + 1] - a) * fraction;
        var phase = _phases[r] + _increments[r];
        _phases[r] = phase >= 1 ? phase - 1 : phase;
      }
      out[i] += sample * level * voiceGain;
    }
    _level = level;
  }
}
