# milomedy_midi_synth_sf2

The SoundFont synth of the MIDI engine (`milomedy_midi_engine`), pure Dart (VM,
dart2js, dart2wasm, Flutter). No SoundFont inside: bring an `.sf2` file (General
MIDI ones like GeneralUser GS work).

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
- `midi_render` renders a MIDI file to WAV from the command line.

Only the synthesizer of dart_melty_soundfont is imported. Its main library exports
`midi_file.dart`, which dart2js cannot compile because of a 64-bit integer
literal.

## Getting started

Not on pub.dev, git dependencies (the engine too):

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

Render a MIDI file with a SoundFont to a WAV file (Dart VM):

```dart
import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

Future<void> main() async {
  var soundFont = MidiSoundFont.fromBytes(await File('gm.sf2').readAsBytes());
  print('${soundFont.name}: ${soundFont.presets.length} presets');
  var song = MidiSong.fromBytes(await File('song.mid').readAsBytes());
  var engine = MidiEngine(
    sampleRate: 44100,
    synths: [MidiSoundFontSynth(soundFont)],
  );
  var samples = midiRenderOffline(engine, song.toTimeline());
  await File('song.wav').writeAsBytes(midiWavBytes(samples, sampleRate: 44100));
}
```

Or in a hosted player (isolate or AudioWorklet; `midiCreatePlayer` of
`milomedy_midi_audio_stream` in a Flutter app):

```dart
import 'dart:typed_data';

import 'package:milomedy_midi_engine/isolate_player.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

Future<MidiIsolatePlayer> soundFontPlayer(
  MidiPcmStreamOpener openStream,
  Uint8List bytes,
) async {
  var player = await MidiIsolatePlayer.spawn(
    synths: [const MidiSynthSpec(soundFont: 'gm')],
    openStream: openStream, // midiMpAudioStreamOpener in a Flutter app
    setup: midiSoundFontRegister,
  );
  // The track is silent until its SoundFont is loaded.
  await player.loadSoundFont('gm', bytes);
  return player;
}
```

## Good to know

- `MidiSoundFont.fromBytes` throws on a file that is not a SoundFont; read
  it once and share it between synths.
- A `MidiSynthSpec(soundFont: id)` track plays only where
  `midiSoundFontRegister` ran (the isolate `setup`, or the worklet built by
  `setup_web_worklet` with this package in the app) and after
  `loadSoundFont(id, bytes)`.
- A program missing from the SoundFont falls back to the General MIDI one of
  bank 0 (bank 128 program 0 for the drums), then to the preset of the lowest
  bank and program.
- The tests use `midiTinySoundFontBytes()`: no file to download.

## midi_render

Renders a MIDI file to a 16 bit stereo WAV file, with a SoundFont or, without
one, with the accordion reed and the metronome click:

```
dart run milomedy_midi_synth_sf2:midi_render --soundfont gm.sf2 [-o out.wav] [--rate 44100] [--speed 1] [--transpose 0] song.mid
```

`--rate` and `--speed` must be positive. Exit codes: 64 bad arguments, 65 not
a MIDI file or not a SoundFont, 66 a file that cannot be read.

## Speed

`dart run tool/benchmark.dart <file.sf2> <file.mid>` measures the real-time
factor. On 2026-10-29, on an Apple silicon Mac, with `pop.mid` (110 s, 1025 notes),
reverb and chorus on, in blocks of 128 frames:

| Build | One-preset SoundFont (589 KB) | GeneralUser GS 2.0.3 (32 MB) | Reading GeneralUser GS |
|---|---|---|---|
| VM (JIT) | 83x | 58x | 116 ms |
| AOT | 95x | 62x | 45 ms |
| dart2js (Chrome) | 75x | 50x | 131 ms |
| dart2wasm (Chrome) | 29x | 18x | 504 ms |

It also renders one track per channel, as an app's mixer does, mixed by the
hosts' `MidiStereoMixdown`: 16 synths with their reverb and chorus, 16 dry
synths, and 16 dry synths sending to the shared reverb of the engine (their CC
91, 40 when none). On 2026-11-17, on a Linux x64 desktop (other work running),
`pop.mid` with GeneralUser GS 2.0.3, blocks of 128 frames:

| Build | 1 synth, effects | 16 synths, effects | 16 dry synths | 16 dry synths + shared reverb |
|---|---|---|---|---|
| VM (JIT) | 68.6x | 15.3x | 65.9x | 51.7x |
| AOT | 80.4x | 15.5x | 76.5x | 56.5x |
| dart2js (Chrome) | 57.1x | 9.1x | 35.8x | 33.4x |
| dart2wasm (Chrome) | 9.9x | 2.1x | 10.9x | 8.9x |

In a browser, by hand: copy the files to `.local/benchmark/sound_font.sf2` and
`.local/benchmark/song.mid`, then
`dart test -p chrome test/benchmark_web_test_manual.dart` (add `-c dart2wasm`
for wasm). It runs `tool/benchmark_lines.dart`, which has no `dart:io`.

## Shared reverb and tuning

- One track per channel: give each a dry synth (`MidiSynthSpec(soundFont: id,
  effects: false)`) and send it to the shared reverb of the engine
  (`player.setReverb(track, send)`, the sends of `midiReverbSends`). At the
  default send of melty (40 / 127), a dry track on the bus sounds as the synth
  with its own reverb while its notes hold, to the rounding of the floats; in a
  release, melty stops feeding its own reverb once a voice is quiet, the bus
  does not (a test compares them).
- `player.tuneCents` (or `MidiEngine.tuneCents`) reaches the synth as RPN 1,
  which dart_melty_soundfont 2.0.0 handles: the voices sounding follow at once.
  The tiny SoundFont's 440 Hz sine plays at 442.0 Hz at +7.85 cents, in the
  engine, the isolate host and the AudioWorklet. The percussion channel is not
  tuned.
