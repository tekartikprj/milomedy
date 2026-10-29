/// The SoundFont tracks of the engine hosts: registers the SoundFont synth
/// where a host runs.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';

import 'sound_font.dart';
import 'sound_font_synth.dart';

class _Support implements MidiSoundFontSupport {
  @override
  Object parse(Uint8List bytes) => MidiSoundFont.fromBytes(bytes);

  @override
  MidiSynth synth(Object soundFont, int sampleRate, {bool effects = true}) =>
      MidiSoundFontSynth(
        soundFont as MidiSoundFont,
        sampleRate: sampleRate,
        reverbAndChorus: effects,
      );
}

/// Registers the SoundFont synth in this isolate or worklet, so that the
/// engine host plays the tracks whose spec has a `soundFont`.
///
/// - The isolate player: pass it as the `setup` of
///   `MidiIsolatePlayer.spawn`.
/// - The AudioWorklet player: nothing to do, `setup_web_worklet` calls it
///   when the app depends on this package.
void midiSoundFontRegister() => midiSoundFontSupport ??= _Support();
