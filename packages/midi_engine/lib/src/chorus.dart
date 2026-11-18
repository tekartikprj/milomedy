/// A chorus in pure Dart, and the shared chorus bus of a mix: each track
/// sends to it at its own level (its panned left and right), the bus adds
/// its output to the mix.
///
/// [MidiChorus] is a port of the chorus of dart_melty_soundfont 2.0.0
/// (`lib/chorus.dart`; MIT, Copyright (C) 2021 Nobuaki Tanaka (MeltySynth),
/// Copyright (C) 2022 Charles Weinberger (DartMeltySoundFont)): a delay of
/// 2 ms swept by 1.9 ms at 0.4 Hz, the right side a quarter of a period
/// after the left one, as the chorus of a SoundFont synth with its effects
/// on.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One side of the chorus: a delay line read at a swept position.
class _ChorusSide {
  final Float32List buffer;
  final Float32List delays;
  var index = 0;
  var delayIndex = 0;

  _ChorusSide(int size, this.delays, this.delayIndex)
    : buffer = Float32List(size);

  void mute() => buffer.fillRange(0, buffer.length, 0);

  /// Writes the delayed [input] into [output] (replacing it), [count]
  /// frames.
  void process(Float32List input, Float32List output, int count) {
    var buffer = this.buffer;
    var size = buffer.length;
    var delays = this.delays;
    var delayCount = delays.length;
    var index = this.index;
    var delayIndex = this.delayIndex;
    for (var i = 0; i < count; i++) {
      var position = index - delays[delayIndex];
      if (position < 0) {
        position += size;
      }
      var index1 = position.toInt();
      var index2 = index1 + 1;
      if (index2 == size) {
        index2 = 0;
      }
      var x1 = buffer[index1];
      var x2 = buffer[index2];
      output[i] = x1 + (position - index1) * (x2 - x1);
      buffer[index] = input[i];
      if (++index == size) {
        index = 0;
      }
      if (++delayIndex == delayCount) {
        delayIndex = 0;
      }
    }
    this.index = index;
    this.delayIndex = delayIndex;
  }
}

/// A stereo chorus (wet only): each side delayed by a swept delay.
class MidiChorus {
  /// The delay in the middle of the sweep, in seconds.
  static const delay = 0.002;

  /// How far the delay sweeps each way, in seconds.
  static const depth = 0.0019;

  /// The rate of the sweep, in Hz.
  static const frequency = 0.4;

  /// The sample rate.
  final int sampleRate;

  final _ChorusSide _left;
  final _ChorusSide _right;

  MidiChorus._(this.sampleRate, this._left, this._right);

  /// A chorus at [sampleRate].
  factory MidiChorus({required int sampleRate}) {
    var delays = Float32List((sampleRate / frequency).round());
    for (var t = 0; t < delays.length; t++) {
      var phase = 2 * math.pi * t / delays.length;
      delays[t] = sampleRate * (delay + depth * math.sin(phase));
    }
    var size = (sampleRate * (delay + depth) + 2).toInt();
    return MidiChorus._(
      sampleRate,
      _ChorusSide(size, delays, 0),
      _ChorusSide(size, delays, delays.length ~/ 4),
    );
  }

  /// Writes the chorus of [inputLeft] and [inputRight] into [outputLeft]
  /// and [outputRight] (replacing them), [count] frames.
  void process(
    Float32List inputLeft,
    Float32List inputRight,
    Float32List outputLeft,
    Float32List outputRight,
    int count,
  ) {
    _left.process(inputLeft, outputLeft, count);
    _right.process(inputRight, outputRight, count);
  }

  /// Silences what it still holds.
  void mute() {
    _left.mute();
    _right.mute();
  }
}

/// The shared chorus of a mix: the tracks add what they send to
/// [inputLeft] and [inputRight], [process] renders the chorus into [left]
/// and [right], which the mix adds times [level]. Idle (no cost) while
/// nothing was sent and its delay line has emptied.
class MidiChorusBus {
  /// The chorus.
  final MidiChorus chorus;

  /// The level of the chorus in the mix, 0 to 1 (more is louder).
  var level = 1.0;

  var _inputLeft = Float32List(0);
  var _inputRight = Float32List(0);
  var _left = Float32List(0);
  var _right = Float32List(0);

  /// The frames after which the delay line is empty (its length, rounded
  /// up).
  final int _tailFrames;
  var _quiet = 0;
  var _idle = true;

  /// A bus at [sampleRate].
  MidiChorusBus({required int sampleRate})
    : chorus = MidiChorus(sampleRate: sampleRate),
      _tailFrames =
          (sampleRate * (MidiChorus.delay + MidiChorus.depth)).ceil() + 2;

  /// True while silent: nothing sent, its delay line empty. [process] then
  /// does nothing (no cost).
  bool get idle => _idle;

  /// The inputs of the next [process] of [frames] frames, zeroed: the
  /// tracks add their panned left and right samples times their send.
  (Float32List, Float32List) input(int frames) {
    _ensure(frames);
    _inputLeft.fillRange(0, frames, 0);
    _inputRight.fillRange(0, frames, 0);
    return (_inputLeft, _inputRight);
  }

  void _ensure(int frames) {
    if (_inputLeft.length < frames) {
      _inputLeft = Float32List(frames);
      _inputRight = Float32List(frames);
      _left = Float32List(frames);
      _right = Float32List(frames);
    }
  }

  /// The left input of the block being fed (after [input]).
  Float32List get inputLeft => _inputLeft;

  /// The right input of the block being fed (after [input]).
  Float32List get inputRight => _inputRight;

  /// The left output of the last [process].
  Float32List get left => _left;

  /// The right output of the last [process].
  Float32List get right => _right;

  /// Renders the chorus of the [frames] of the inputs into [left] and
  /// [right] ([fed]: [input] was called for this block); false, nothing
  /// rendered, when idle: silent in, its delay line empty.
  bool process(int frames, {required bool fed}) {
    if (!fed) {
      if (_idle) {
        return false;
      }
      input(frames);
    }
    var sent = false;
    for (var i = 0; i < frames; i++) {
      if (_inputLeft[i] != 0 || _inputRight[i] != 0) {
        sent = true;
        break;
      }
    }
    if (!sent && _idle) {
      return false;
    }
    _idle = false;
    chorus.process(_inputLeft, _inputRight, _left, _right, frames);
    if (sent) {
      _quiet = 0;
    } else {
      // Nothing in: idle once the delay line has emptied.
      _quiet += frames;
      if (_quiet >= _tailFrames) {
        mute();
      }
    }
    return true;
  }

  /// Silences it at once: idle.
  void mute() {
    chorus.mute();
    _idle = true;
    _quiet = 0;
  }
}
