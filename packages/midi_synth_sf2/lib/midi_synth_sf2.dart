/// The SoundFont synth of the MIDI engine: [MidiSoundFont] reads a SoundFont,
/// [MidiSoundFontSynth] plays it (dart_melty_soundfont), and
/// [midiSoundFontRegister] makes the engine hosts (isolate, AudioWorklet)
/// play it. No SoundFont inside: [midiTinySoundFontBytes] makes a tiny one
/// for the tests.
library;

import 'src/register.dart';
import 'src/sound_font.dart';
import 'src/sound_font_synth.dart';
import 'src/tiny_sound_font.dart';

export 'src/register.dart';
export 'src/sound_font.dart';
export 'src/sound_font_synth.dart';
export 'src/tiny_sound_font.dart';
