/// A reverb in pure Dart, and the shared reverb bus of a mix: each track
/// sends to it at its own level, the bus adds its output to the mix.
///
/// [MidiReverb] is a port of the reverb of dart_melty_soundfont 2.0.0
/// (`lib/reverb.dart`, `reverb_comb_filter.dart`, `reverb_all_pass_filter.dart`;
/// MIT, Copyright (C) 2021 Nobuaki Tanaka (MeltySynth), Copyright (C) 2022
/// Charles Weinberger (DartMeltySoundFont)), itself based on Freeverb, a
/// public domain reverb by Jezar at Dreampoint: the same filters and
/// tunings, so a track sending to it sounds as the reverb of a SoundFont
/// synth with its effects on.
library;

import 'dart:typed_data';

/// A comb filter with a low pass in its feedback loop.
class _Comb {
  final Float32List buffer;
  var index = 0;
  var store = 0.0;
  var feedback = 0.0;
  var damp1 = 0.0;
  var damp2 = 1.0;

  _Comb(int size) : buffer = Float32List(size);

  void mute() {
    buffer.fillRange(0, buffer.length, 0);
    store = 0;
  }

  /// Adds the output of [input] to [output], [count] frames.
  void process(Float32List input, Float32List output, int count) {
    var buffer = this.buffer;
    var size = buffer.length;
    var index = this.index;
    var store = this.store;
    var feedback = this.feedback;
    var damp1 = this.damp1;
    var damp2 = this.damp2;
    for (var i = 0; i < count; i++) {
      var out = buffer[index];
      // Denormal numbers are slow: flushed to zero.
      if (out.abs() < 1e-6) {
        out = 0.0;
      }
      store = out * damp2 + store * damp1;
      if (store.abs() < 1e-6) {
        store = 0.0;
      }
      buffer[index] = input[i] + store * feedback;
      output[i] += out;
      if (++index == size) {
        index = 0;
      }
    }
    this.index = index;
    this.store = store;
  }
}

/// An all-pass filter.
class _AllPass {
  final Float32List buffer;
  var index = 0;
  static const feedback = 0.5;

  _AllPass(int size) : buffer = Float32List(size);

  void mute() => buffer.fillRange(0, buffer.length, 0);

  /// Filters [block] in place, [count] frames.
  void process(Float32List block, int count) {
    var buffer = this.buffer;
    var size = buffer.length;
    var index = this.index;
    for (var i = 0; i < count; i++) {
      var input = block[i];
      var out = buffer[index];
      if (out.abs() < 1e-6) {
        out = 0.0;
      }
      block[i] = out - input;
      buffer[index] = input + out * feedback;
      if (++index == size) {
        index = 0;
      }
    }
    this.index = index;
  }
}

/// A Freeverb style reverb: a mono input, a stereo output (wet only).
class MidiReverb {
  /// The gain of the input, as in Freeverb: a send of 1 feeds the reverb
  /// with the sum of the left and right samples times this.
  static const inputGain = 0.015;

  static const _scaleWet = 3.0;
  static const _scaleDamp = 0.4;
  static const _scaleRoom = 0.28;
  static const _offsetRoom = 0.7;
  static const _stereoSpread = 23;
  static const _combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _allPassTunings = [556, 441, 341, 225];

  /// The sample rate.
  final int sampleRate;

  final List<_Comb> _combsLeft;
  final List<_Comb> _combsRight;
  final List<_AllPass> _allPassesLeft;
  final List<_AllPass> _allPassesRight;

  double _roomSize;
  double _damp;
  double _wet;
  double _stereoWidth;
  var _wet1 = 0.0;
  var _wet2 = 0.0;

  static int _scale(int sampleRate, int tuning) =>
      (sampleRate / 44100 * tuning).round();

  /// A reverb at [sampleRate]: [roomSize], [damp], [wet] and [width] from 0
  /// to 1 (dart_melty_soundfont's settings by default).
  MidiReverb({
    required this.sampleRate,
    double roomSize = 0.5,
    double damp = 0.5,
    double wet = 1 / 3,
    double width = 1,
  }) : _combsLeft = [
         for (var tuning in _combTunings) _Comb(_scale(sampleRate, tuning)),
       ],
       _combsRight = [
         for (var tuning in _combTunings)
           _Comb(_scale(sampleRate, tuning + _stereoSpread)),
       ],
       _allPassesLeft = [
         for (var tuning in _allPassTunings)
           _AllPass(_scale(sampleRate, tuning)),
       ],
       _allPassesRight = [
         for (var tuning in _allPassTunings)
           _AllPass(_scale(sampleRate, tuning + _stereoSpread)),
       ],
       _roomSize = roomSize * _scaleRoom + _offsetRoom,
       _damp = damp * _scaleDamp,
       _wet = wet * _scaleWet,
       _stereoWidth = width {
    _update();
  }

  void _update() {
    _wet1 = _wet * (_stereoWidth / 2 + 0.5);
    _wet2 = _wet * ((1 - _stereoWidth) / 2);
    for (var comb in [..._combsLeft, ..._combsRight]) {
      comb
        ..feedback = _roomSize
        ..damp1 = _damp
        ..damp2 = 1 - _damp;
    }
  }

  /// The size of the room, 0 to 1: the length of the tail.
  double get roomSize => (_roomSize - _offsetRoom) / _scaleRoom;

  set roomSize(double value) {
    _roomSize = value * _scaleRoom + _offsetRoom;
    _update();
  }

  /// The damping of the high frequencies, 0 to 1.
  double get damp => _damp / _scaleDamp;

  set damp(double value) {
    _damp = value * _scaleDamp;
    _update();
  }

  /// The level of the output, 0 to 1.
  double get wet => _wet / _scaleWet;

  set wet(double value) {
    _wet = value * _scaleWet;
    _update();
  }

  /// The stereo width, 0 (mono) to 1.
  double get width => _stereoWidth;

  set width(double value) {
    _stereoWidth = value;
    _update();
  }

  /// Replaces the first [count] frames of [left] and [right] with the reverb
  /// of [input] (mono, [inputGain] already applied).
  void process(
    Float32List input,
    Float32List left,
    Float32List right,
    int count,
  ) {
    left.fillRange(0, count, 0);
    right.fillRange(0, count, 0);
    for (var comb in _combsLeft) {
      comb.process(input, left, count);
    }
    for (var allPass in _allPassesLeft) {
      allPass.process(left, count);
    }
    for (var comb in _combsRight) {
      comb.process(input, right, count);
    }
    for (var allPass in _allPassesRight) {
      allPass.process(right, count);
    }
    // With the default settings (a wet of 1, a full width): as it is.
    if (1 - _wet1 > 1e-3 || _wet2 > 1e-3) {
      for (var i = 0; i < count; i++) {
        var l = left[i];
        var r = right[i];
        left[i] = l * _wet1 + r * _wet2;
        right[i] = r * _wet1 + l * _wet2;
      }
    }
  }

  /// Silences the tail at once.
  void mute() {
    for (var comb in _combsLeft) {
      comb.mute();
    }
    for (var comb in _combsRight) {
      comb.mute();
    }
    for (var allPass in _allPassesLeft) {
      allPass.mute();
    }
    for (var allPass in _allPassesRight) {
      allPass.mute();
    }
  }
}

/// The shared reverb of a mix: the tracks add what they send to [input],
/// [process] renders the reverb into [left] and [right], which the mix adds
/// times [level]. Idle (no cost) while nothing was sent and the tail has
/// died out.
class MidiReverbBus {
  /// The reverb.
  final MidiReverb reverb;

  /// The level of the reverb in the mix, 0 to 1 (more is louder).
  var level = 1.0;

  var _input = Float32List(0);
  var _left = Float32List(0);
  var _right = Float32List(0);

  /// The frames of silence after which the tail is over.
  final int _tailFrames;
  var _quiet = 0;
  var _idle = true;

  /// A bus at [sampleRate].
  MidiReverbBus({required int sampleRate})
    : reverb = MidiReverb(sampleRate: sampleRate),
      _tailFrames = (0.1 * sampleRate).round();

  /// True while silent: nothing sent, its tail over. [process] then does
  /// nothing (no cost).
  bool get idle => _idle;

  /// The input of the next [process] of [frames] frames, zeroed: the tracks
  /// add the sum of their left and right samples times their send.
  Float32List input(int frames) {
    _ensure(frames);
    _input.fillRange(0, frames, 0);
    return _input;
  }

  void _ensure(int frames) {
    if (_input.length < frames) {
      _input = Float32List(frames);
      _left = Float32List(frames);
      _right = Float32List(frames);
    }
  }

  /// The left output of the last [process].
  Float32List get left => _left;

  /// The right output of the last [process].
  Float32List get right => _right;

  /// Renders the reverb of the [frames] of [input] into [left] and [right]
  /// ([fed]: [input] was called for this block); false, nothing rendered,
  /// when idle: silent in, its tail over.
  bool process(int frames, {required bool fed}) {
    if (!fed) {
      if (_idle) {
        return false;
      }
      input(frames);
    }
    var samples = _input;
    var sent = false;
    for (var i = 0; i < frames; i++) {
      var sample = samples[i];
      if (sample != 0) {
        sent = true;
        samples[i] = sample * MidiReverb.inputGain;
      }
    }
    if (!sent && _idle) {
      return false;
    }
    _idle = false;
    reverb.process(samples, _left, _right, frames);
    if (sent) {
      _quiet = 0;
    } else {
      // Nothing in: idle once the tail is under the level the filters
      // flush to zero for a while.
      var peak = 0.0;
      for (var i = 0; i < frames; i++) {
        var l = _left[i].abs();
        var r = _right[i].abs();
        if (l > peak) {
          peak = l;
        }
        if (r > peak) {
          peak = r;
        }
      }
      _quiet = peak < 1e-6 ? _quiet + frames : 0;
      if (_quiet >= _tailFrames) {
        mute();
      }
    }
    return true;
  }

  /// Silences the tail at once: idle.
  void mute() {
    reverb.mute();
    _idle = true;
    _quiet = 0;
  }
}
