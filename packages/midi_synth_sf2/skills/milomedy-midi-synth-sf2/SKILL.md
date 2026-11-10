---
name: milomedy-midi-synth-sf2
description: >-
  Use when playing or rendering MIDI with a SoundFont (.sf2) in the milomedy
  MIDI engine with milomedy_midi_synth_sf2: MidiSoundFont (fromBytes, name,
  presets, presetName), MidiSoundFontSynth (a MidiSynth on
  dart_melty_soundfont, reverbAndChorus, maximumPolyphony),
  midiSoundFontRegister for the isolate and AudioWorklet players
  (MidiSynthSpec(soundFont:), loadSoundFont), midiTinySoundFontBytes for
  tests, and the midi_render command (MIDI file to WAV).
---

# SoundFonts in the MIDI engine (milomedy_midi_synth_sf2)

Pure Dart (VM, dart2js, dart2wasm, Flutter): a SoundFont read by
`MidiSoundFont` and played by `MidiSoundFontSynth`, a `MidiSynth` of
`milomedy_midi_synth` that `milomedy_midi_engine` drives like any other
(one synth per track). No SoundFont is shipped.

## Guidelines

* Dependencies (git, public repo, not on pub.dev): this package and
  `milomedy_midi_engine`:
  ```yaml
  dependencies:
    milomedy_midi_synth_sf2:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_synth_sf2
    milomedy_midi_engine:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_engine
  ```
* Import `package:milomedy_midi_synth_sf2/midi_synth_sf2.dart`. Never import
  `package:dart_melty_soundfont/dart_melty_soundfont.dart` in web code: it
  exports `midi_file.dart`, which dart2js cannot compile (this package
  imports only the synthesizer).
* `MidiSoundFont.fromBytes(bytes)` parses once (32 MB General MIDI file:
  about 0.1 s on the VM, 0.5 s in dart2wasm); share it between synths.
  `presets` are sorted by bank then program, `presetName(bank, program)` is
  null when missing. A file that is not a SoundFont throws.
* `MidiSoundFontSynth(soundFont, sampleRate: 44100, maximumPolyphony: 64,
  reverbAndChorus: true)`: the 16 General MIDI channels, program change and
  bank select (CC 0) per channel, the drum kits (bank 128) on the
  percussion channel (`midiPercussionChannel`, 9). A missing program falls
  back to bank 0 (bank 128 program 0 for drums), then to the preset of the
  lowest bank and program. Messages take effect at the next 64 frame block.
* Engine directly (offline, tests, a custom sink): `MidiEngine(sampleRate:,
  synths: [MidiSoundFontSynth(soundFont)])`, then `midiRenderOffline` and
  `midiWavBytes`.
* Hosted players (`MidiIsolatePlayer`, `MidiWorkletPlayer`, or
  `midiCreatePlayer` of `milomedy_midi_audio_stream`): declare the track as
  `const MidiSynthSpec(soundFont: 'gm')`, register the support where the
  engine runs (`setup: midiSoundFontRegister` for the isolate player,
  `isolateSetup:` for `midiCreatePlayer`; on the web
  `dart run milomedy_midi_engine:setup_web_worklet` puts it in the worklet
  when the app depends on this package), then
  `await player.loadSoundFont('gm', bytes)`; the track is silent before.
* Tests: `midiTinySoundFontBytes()` builds a 9774 byte SoundFont in code (a
  looped 440 Hz sine on bank 0 that every program falls back to, a 0.1 s
  noise on bank 128). Render with `reverbAndChorus: false` to get the
  samples as they are. The MIDI constants (`midiNoteOn`,
  `midiControlChange`, `midiPercussionChannel`...) come from
  `package:milomedy_midi_synth/midi_synth.dart`: add `milomedy_midi_synth`
  (same repository, `packages/midi_synth`) to the pubspec to import it.
* `midi_render` (`dart run milomedy_midi_synth_sf2:midi_render [--soundfont
  gm.sf2] [-o out.wav] [--rate 44100] [--speed 1] [--transpose 0]
  song.mid`): without a SoundFont, the accordion reed and the click play.
  `--rate` and `--speed` must be positive; exit 64 bad arguments, 65 not a
  MIDI file or SoundFont, 66 unreadable file. The whole song is rendered in
  memory.

## Examples

### A General MIDI file to WAV

```dart
import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

Future<void> renderToWav(String sf2, String mid, String wav) async {
  var soundFont = MidiSoundFont.fromBytes(await File(sf2).readAsBytes());
  var song = MidiSong.fromBytes(await File(mid).readAsBytes());
  var engine = MidiEngine(
    sampleRate: 44100,
    synths: [MidiSoundFontSynth(soundFont)],
  );
  var samples = midiRenderOffline(engine, song.toTimeline());
  await File(wav).writeAsBytes(midiWavBytes(samples, sampleRate: 44100));
}
```

### A synth test with the tiny SoundFont

```dart
import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';

void main() {
  test('a note sounds', () {
    var synth = MidiSoundFontSynth(
      MidiSoundFont.fromBytes(midiTinySoundFontBytes()),
      reverbAndChorus: false,
    )..send(midiNoteOn, 69, 127);
    var left = Float32List(4410);
    var right = Float32List(4410);
    synth.render(left, right, 0, left.length);
    expect(left.any((sample) => sample.abs() > 0.05), isTrue);
  });
}
```
