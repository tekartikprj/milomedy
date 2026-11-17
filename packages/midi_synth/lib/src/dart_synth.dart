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

/// An instrument that can be tuned: [DartSynth] gives it the tuning of the
/// channel (RPN 1 and 2) in [cents]. The others play in tune.
abstract interface class DartTunableInstrument implements DartInstrument {
  /// The voice of [key] at [velocity] (0 to 1) rendered at [sampleRate],
  /// [cents] above its pitch (a frequency factor of 2^(cents / 1200)), null
  /// when the instrument has no sound for [key].
  @override
  DartVoice? voice(
    int key,
    double velocity,
    int sampleRate, {
    double cents = 0,
  });
}

/// The state of a channel.
class _Channel {
  var program = 0;
  var volume = midiDefaultVolume;
  var expression = 127;
  var sustain = false;

  /// The registered parameter selected (RPN), [midiRpnNull] when none.
  var rpn = midiRpnNull;

  /// The fine tuning (RPN 1), 14 bits, 8192 in tune.
  var fineTuning = 8192;

  /// The coarse tuning (RPN 2), in semitones.
  var coarseTuning = 0;

  /// The tuning, in cents.
  double get cents => coarseTuning * 100 + midiFineTuningCents(fineTuning);

  /// As dart_melty_soundfont: the tuning is reset too.
  void resetControllers() {
    expression = 127;
    sustain = false;
    rpn = midiRpnNull;
    fineTuning = 8192;
    coarseTuning = 0;
  }

  void dataEntry(int value, {required bool low}) {
    switch (rpn) {
      case midiRpnFineTuning:
        fineTuning = low
            ? (fineTuning & 0x3f80) | value
            : (fineTuning & 0x7f) | (value << 7);
      case midiRpnCoarseTuning when !low:
        coarseTuning = value - 64;
    }
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
///
/// The tuning of a channel (RPN 1, fine, and RPN 2, coarse) tunes the next
/// notes of its [DartTunableInstrument]s (the reeds, the click); the notes
/// sounding keep their pitch.
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
        var instrument = _instrumentOf(channel);
        var cents = _channels[channel].cents;
        var voice = instrument is DartTunableInstrument && cents != 0
            ? instrument.voice(data1, data2 / 127, sampleRate, cents: cents)
            : instrument?.voice(data1, data2 / 127, sampleRate);
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
      case midiControllerRpnMsb:
        state.rpn = (state.rpn & 0x7f) | (value << 7);
      case midiControllerRpnLsb:
        state.rpn = (state.rpn & 0x3f80) | value;
      case midiControllerDataEntry:
        state.dataEntry(value, low: false);
      case midiControllerDataEntryLsb:
        state.dataEntry(value, low: true);
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
