/// The SoundFont synth: dart_melty_soundfont behind the MidiSynth interface.
library;

import 'dart:typed_data';

// Not the main library: it exports midi_file.dart, which dart2js cannot
// compile (a 64-bit integer literal).
import 'package:dart_melty_soundfont/synthesizer.dart';
import 'package:dart_melty_soundfont/synthesizer_settings.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';

import 'sound_font.dart';

/// A synth playing [soundFont]: the 16 channels of General MIDI, the drum
/// kits (bank 128) on the percussion channel, reverb and chorus.
///
/// It renders in internal blocks of 64 frames: a message is heard from the
/// next one (1.45 ms at 44.1 kHz).
class MidiSoundFontSynth implements MidiSynth {
  /// The SoundFont played.
  final MidiSoundFont soundFont;

  @override
  final int sampleRate;

  final Synthesizer _synth;

  /// A synth of [soundFont] at [sampleRate], of at most [maximumPolyphony]
  /// voices, with or without [reverbAndChorus].
  MidiSoundFontSynth(
    this.soundFont, {
    this.sampleRate = 44100,
    int maximumPolyphony = 64,
    bool reverbAndChorus = true,
  }) : _synth = Synthesizer.load(
         soundFont.soundFont,
         SynthesizerSettings(
           sampleRate: sampleRate,
           maximumPolyphony: maximumPolyphony,
           enableReverbAndChorus: reverbAndChorus,
         ),
       );

  @override
  void send(int status, int data1, [int data2 = 0]) =>
      _synth.processMidiMessage(
        channel: status & 0x0f,
        command: status & 0xf0,
        data1: data1,
        data2: data2,
      );

  @override
  void reset() => _synth.reset();

  @override
  int get activeVoiceCount => _synth.activeVoiceCount();

  @override
  void render(Float32List left, Float32List right, int start, int count) =>
      _synth.render(
        Float32List.sublistView(left, start, start + count),
        Float32List.sublistView(right, start, start + count),
      );
}
