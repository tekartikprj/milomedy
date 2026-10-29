# milomedy_midi_synth_sf2

The SoundFont synth of the MIDI engine (`milomedy_midi_engine`), pure Dart (VM,
dart2js, dart2wasm). No SoundFont inside.

- `MidiSoundFont` reads an `.sf2` file: its name, copyright, author, and its
  presets (bank, program, name).
- `MidiSoundFontSynth` plays it as a `MidiSynth`, with
  [dart_melty_soundfont](https://pub.dev/packages/dart_melty_soundfont):
  - the 16 channels of General MIDI, with the drum kits (bank 128) on the
    percussion channel;
  - reverb and chorus, which can be turned off;
  - 64 voices by default.
  It renders in internal blocks of 64 frames, so a message is heard from the next
  block (1.45 ms at 44.1 kHz).
- `midiSoundFontRegister()` makes the engine hosts play the tracks whose spec has
  a `soundFont`:
  - the isolate player: pass it as `setup`;
  - the AudioWorklet player: `setup_web_worklet` calls it when the app depends on
    this package.
- `midiTinySoundFontBytes()` makes a tiny SoundFont in code, for the tests: a
  looped 440 Hz sine on bank 0, and a short noise on bank 128.

Only the synthesizer of dart_melty_soundfont is imported. Its main library exports
`midi_file.dart`, which dart2js cannot compile because of a 64-bit integer
literal.

## Setup

```yaml
dependencies:
  milomedy_midi_synth_sf2:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_synth_sf2
```

## Use

```dart
var soundFont = MidiSoundFont.fromBytes(await File('gm.sf2').readAsBytes());
var engine = MidiEngine(
  sampleRate: 44100,
  synths: [MidiSoundFontSynth(soundFont)],
);
```

Or in a hosted player (isolate or AudioWorklet):

```dart
var player = await MidiIsolatePlayer.spawn(
  synths: [const MidiSynthSpec(soundFont: 'gm')],
  openStream: midiMpAudioStreamOpener,
  setup: midiSoundFontRegister,
);
await player.loadSoundFont('gm', bytes);
```

## midi_render

Renders a MIDI file to WAV, with a SoundFont or, without one, with the accordion
reed and the metronome click:

```
dart run milomedy_midi_synth_sf2:midi_render --soundfont gm.sf2 [-o out.wav] [--rate 44100] [--speed 1] [--transpose 0] song.mid
```

## Speed

`dart run tool/benchmark.dart <file.sf2> <file.mid>` measures the real-time
factor. On 2026-10-29, on an Apple silicon Mac, with `pop.mid` (110 s, 1025 notes)
and a one-preset SoundFont:

| Build | Blocks of 128 frames | Blocks of 2048 |
|---|---|---|
| VM (JIT) | 83x | 92x |
| AOT | 95x | 95x |
| dart2js (Chrome) | 75x | 78x |
| dart2wasm (Chrome) | 29x | 29x |
