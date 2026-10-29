/// The SoundFont tracks of an engine host: the engine does not know
/// SoundFonts (a metronome must not pay for them), the SoundFont package
/// registers itself where the host runs.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';

/// Reads SoundFonts and makes their synths: set in [midiSoundFontSupport]
/// by `milomedy_midi_synth_sf2` (`midiSoundFontRegister()`).
abstract class MidiSoundFontSupport {
  /// The SoundFont of [bytes] (an `.sf2` file), shared by the synths of
  /// [synth].
  Object parse(Uint8List bytes);

  /// A synth of [soundFont] (from [parse]) at [sampleRate].
  MidiSynth synth(Object soundFont, int sampleRate);
}

/// The SoundFont support of this isolate or worklet, null when not
/// registered: the SoundFont tracks then stay silent.
MidiSoundFontSupport? midiSoundFontSupport;

/// A synth set later (a SoundFont synth, once its SoundFont is received):
/// silent until then.
class MidiDeferredSynth implements MidiSynth {
  @override
  final int sampleRate;

  /// The synth played, null while silent.
  MidiSynth? synth;

  /// A synth at [sampleRate], silent until [synth] is set.
  MidiDeferredSynth({required this.sampleRate});

  @override
  int get activeVoiceCount => synth?.activeVoiceCount ?? 0;

  @override
  void send(int status, int data1, [int data2 = 0]) =>
      synth?.send(status, data1, data2);

  @override
  void reset() => synth?.reset();

  @override
  void render(Float32List left, Float32List right, int start, int count) {
    var synth = this.synth;
    if (synth == null) {
      left.fillRange(start, start + count, 0);
      right.fillRange(start, start + count, 0);
    } else {
      synth.render(left, right, start, count);
    }
  }
}
