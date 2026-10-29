/// A synth of instruments written in Dart: each program of each channel is
/// an instrument making voices, the synth adds them up.
library;

import 'dart:typed_data';

import 'midi_synth.dart';

/// A note sounding.
abstract class DartVoice {
  /// Adds its next [count] samples, times [gain], to [out] from [start].
  void render(Float32List out, int start, int count, double gain);

  /// Starts its release (a note off).
  void release();

  /// True once silent for good.
  bool get ended;
}

/// An instrument: makes the voices of its notes.
abstract class DartInstrument {
  /// The voice of [key] at [velocity] (0 to 1) rendered at [sampleRate],
  /// null when the instrument has no sound for [key].
  DartVoice? voice(int key, double velocity, int sampleRate);
}

/// The state of a channel.
class _Channel {
  var program = 0;
  var volume = midiDefaultVolume;
  var expression = 127;
  var sustain = false;

  void resetControllers() {
    expression = 127;
    sustain = false;
  }

  /// The gain of the channel volume and expression, a square law as most
  /// General MIDI synths.
  double get gain {
    var value = volume * expression / (127 * 127);
    return value * value;
  }
}

class _Sounding {
  final int channel;
  final int key;
  final DartVoice voice;

  /// Released by its note off.
  var released = false;

  /// Its note off came while the pedal was down.
  var held = false;

  _Sounding(this.channel, this.key, this.voice);
}

/// A synth of [DartInstrument]s. Mono: every voice sounds in the middle
/// (the mixer pans the track). It ignores the pan, pitch bend and pressure
/// messages.
class DartSynth implements MidiSynth {
  @override
  final int sampleRate;

  /// The instrument of the programs that are not in [programs] (none: they
  /// are silent).
  DartInstrument? instrument;

  /// The instrument of each program.
  final Map<int, DartInstrument> programs;

  /// The instrument of the percussion channel, whatever its program (none:
  /// it plays as the other channels).
  DartInstrument? percussion;

  final _channels = List.generate(16, (_) => _Channel());
  final _sounding = <_Sounding>[];

  /// A synth at [sampleRate].
  DartSynth({
    required this.sampleRate,
    this.instrument,
    Map<int, DartInstrument>? programs,
    this.percussion,
  }) : programs = programs ?? {};

  DartInstrument? _instrumentOf(int channel) {
    if (channel == midiPercussionChannel && percussion != null) {
      return percussion;
    }
    return programs[_channels[channel].program] ?? instrument;
  }

  @override
  int get activeVoiceCount => _sounding.length;

  @override
  void send(int status, int data1, [int data2 = 0]) {
    var channel = status & 0x0f;
    switch (status & 0xf0) {
      case midiNoteOn when data2 > 0:
        var voice = _instrumentOf(
          channel,
        )?.voice(data1, data2 / 127, sampleRate);
        if (voice != null) {
          _sounding.add(_Sounding(channel, data1, voice));
        }
      case midiNoteOn:
      case midiNoteOff:
        _noteOff(channel, data1);
      case midiControlChange:
        _control(channel, data1, data2);
      case midiProgramChange:
        _channels[channel].program = data1;
    }
  }

  void _noteOff(int channel, int key) {
    var sustain = _channels[channel].sustain;
    for (var sounding in _sounding) {
      if (sounding.channel == channel &&
          sounding.key == key &&
          !sounding.released &&
          !sounding.held) {
        if (sustain) {
          sounding.held = true;
        } else {
          sounding.released = true;
          sounding.voice.release();
        }
      }
    }
  }

  void _releaseChannel(int channel, {bool held = true}) {
    for (var sounding in _sounding) {
      if (sounding.channel == channel &&
          !sounding.released &&
          (held || sounding.held)) {
        sounding.released = true;
        sounding.voice.release();
      }
    }
  }

  void _control(int channel, int controller, int value) {
    var state = _channels[channel];
    switch (controller) {
      case midiControllerVolume:
        state.volume = value;
      case midiControllerExpression:
        state.expression = value;
      case midiControllerSustain:
        var sustain = value >= 64;
        if (state.sustain && !sustain) {
          _releaseChannel(channel, held: false);
        }
        state.sustain = sustain;
      case midiControllerAllSoundOff:
        _sounding.removeWhere((sounding) => sounding.channel == channel);
      case midiControllerResetAll:
        if (state.sustain) {
          _releaseChannel(channel, held: false);
        }
        state.resetControllers();
      case midiControllerAllNotesOff:
        state.sustain = false;
        _releaseChannel(channel);
    }
  }

  @override
  void reset() {
    _sounding.clear();
    for (var i = 0; i < _channels.length; i++) {
      _channels[i] = _Channel();
    }
  }

  @override
  void render(Float32List left, Float32List right, int start, int count) {
    left.fillRange(start, start + count, 0);
    for (var sounding in _sounding) {
      sounding.voice.render(
        left,
        start,
        count,
        _channels[sounding.channel].gain,
      );
    }
    right.setRange(start, start + count, left, start);
    _sounding.removeWhere((sounding) => sounding.voice.ended);
  }
}
