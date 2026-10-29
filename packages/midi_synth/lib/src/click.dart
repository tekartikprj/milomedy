/// The click of a metronome (from accordelio): a short decaying sine.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_synth.dart';
import 'midi_synth.dart';

/// A metronome click: a sine decaying in [decay] seconds, cut after
/// [length] seconds whatever the note off. The accent keys (the General
/// MIDI hi wood block and metronome bell) sound at [accentFrequency], the
/// other keys at [frequency].
class ClickInstrument implements DartInstrument {
  /// The frequency of the other keys, in Hz.
  final double frequency;

  /// The frequency of the accent keys, in Hz.
  final double accentFrequency;

  /// The keys sounding the accent.
  final Set<int> accentKeys;

  /// The loudness at full velocity.
  final double gain;

  /// The decay time constant, in seconds.
  final double decay;

  /// The length, in seconds.
  final double length;

  /// A click.
  const ClickInstrument({
    this.frequency = 1320,
    this.accentFrequency = 1760,
    this.accentKeys = const {midiKeyHiWoodBlock, 34},
    this.gain = 0.5,
    this.decay = 0.025,
    this.length = 0.06,
  });

  @override
  DartVoice voice(int key, double velocity, int sampleRate) => _ClickVoice(
    (accentKeys.contains(key) ? accentFrequency : frequency) / sampleRate,
    gain * velocity,
    decay * sampleRate,
    (length * sampleRate).round(),
  );
}

class _ClickVoice implements DartVoice {
  final double _increment;
  final double _gain;
  final double _decayFrames;
  final int _frames;
  var _frame = 0;

  _ClickVoice(this._increment, this._gain, this._decayFrames, this._frames);

  @override
  bool get ended => _frame >= _frames;

  /// A percussion: it sounds its whole length.
  @override
  void release() {}

  @override
  void render(Float32List out, int start, int count, double gain) {
    var to = math.min(count, _frames - _frame);
    for (var i = 0; i < to; i++) {
      var t = (_frame + i).toDouble();
      out[start + i] +=
          _gain *
          gain *
          math.exp(-t / _decayFrames) *
          math.sin(2 * math.pi * _increment * t);
    }
    _frame += math.max(0, to);
  }
}
