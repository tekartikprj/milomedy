# milomedy_midi_engine

A MIDI engine in pure Dart (VM, dart2js, dart2wasm), taken from accordelio's
sound engine and generalized from its four parts to tracks and MIDI channels.

## Getting started

Not on pub.dev, a git dependency:

```yaml
dependencies:
  milomedy_midi_engine:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_engine
```

Render a metronome to a WAV file (VM, no sound card needed):

```dart
import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';

Future<void> main() async {
  const sampleRate = 44100;
  var engine = midiMetronomeEngine(sampleRate: sampleRate);
  var timeline = midiMetronomeTimeline(bpm: 100, measures: 2);
  var samples = midiRenderOffline(engine, timeline); // interleaved stereo
  await File(
    'metronome.wav',
  ).writeAsBytes(midiWavBytes(samples, sampleRate: sampleRate));
}
```

A MIDI file is read with `MidiSong.fromBytes(bytes)` (a `FormatException`
for a bad file) and played with `song.toTimeline()`; the instruments are the
synths of `milomedy_midi_synth` (`DartSynth`), one per track.

| Library | Platforms | What |
|---|---|---|
| `midi_engine.dart` | all | timeline, engine, mixer, `MidiPlayer`, offline, WAV, metronome, `MidiSong` |
| `web_audio.dart` | web | `MidiWebAudioSink`, the output of a `MidiPlayer` |
| `web_worklet.dart` | web | `MidiWorkletPlayer`, the engine in an AudioWorklet (module built by `setup_web_worklet`) |
| `isolate_player.dart` | io | `MidiIsolatePlayer`, the engine in an isolate, on a raw stream (`milomedy_midi_audio_stream`) |
| `setup.dart` | io (a tool) | builds the AudioWorklet module |

Common mistakes:

* A web page plays only after a user gesture: call `play()` from a click.
* The engine, its synths and the output must share one sample rate
  (`ArgumentError` otherwise): use the output's (`MidiWebAudioSink.sampleRate`).
* A timeline track without a synth plays nothing (its events are ignored).
* `MidiPlayer` renders on the main isolate, a little ahead: a busy UI can
  make gaps. In an app prefer `MidiWorkletPlayer` (web) or
  `MidiIsolatePlayer` (io).
* `midiRenderOffline` holds the whole song in memory (10 minutes of stereo
  at 44.1 kHz: 212 MB).

## What is in it

- **Timeline.** `MidiTimeline` holds notes (start, duration, key, velocity,
  track, channel) and channel messages (controllers, programs, pitch bend), in
  seconds. A MIDI file, a score, a sequencer project or a generated pattern
  each build one.
- **Engine.** `MidiEngine` plays a timeline with one `MidiSynth` per track.
  - Each event is sent at its exact frame: the synth renders are split there.
  - Loop: blocks are split at the loop end, and release tails carry across
    the jump.
  - Seek with chase: the messages before the new place are sent again, and
    the notes sounding there restart.
  - Speed, which keeps the place in the music.
  - Transpose: a note is released on the key it was played on, and the
    percussion channel is never transposed.
  - Tune (`tuneCents`, -100 to 100 cents): a fine tuning (RPN 1) of each
    melodic channel, sent again after each seek.
  - A speed trainer on the loop (`speedTrainer`): the speed takes a step at the
    frame where the loop starts again.
  - `replace` swaps the timeline in place (an edit).
- **Mixer.** `MidiMixer` sets the volume, pan, mute, solo and reverb send of
  each track, then a master gain and a limiter. One shared reverb (`MidiReverb`,
  a Freeverb) mixes what the tracks send to it. The pan behaves like a Web Audio
  StereoPannerNode, so every output sounds the same.
- **Player.** `MidiPlayer` keeps an output fed a little ahead of its clock and
  reports the song position.
- **Outputs.** All implement `MidiAudioSink`:
  - `MidiStreamSink`: a raw Float32 stream such as `mp_audio_stream`, mixed in
    Dart and pushed 0.1 s ahead.
  - `MidiWebAudioSink` (`web_audio.dart`): an AudioBuffer per block and per
    track, through Web Audio gain and pan nodes.
  - `MidiSilentSink`, for tests.
- **AudioWorklet player** (`web_worklet.dart`). `MidiWorkletPlayer` implements
  `MidiTransport`, like `MidiPlayer`, but the engine runs in an AudioWorklet, on
  the audio thread.
  - The worklet itself is Dart compiled with dart2js. The page can be compiled
    with dart2js or dart2wasm.
  - The processor registers itself from Dart, so the dart2js output is the
    worklet module as it is, with no JS around it.
    `registerProcessor` only needs a constructor whose prototype has `process`:
    a Dart function builds the processor with `Reflect.construct`.
  - The page sends commands through the node's port. The worklet renders each
    128-frame block with the mixer and the limiter, and reports its state and
    position.
  - Nothing is rendered ahead, so a change is heard after the output latency
    only, and a busy page never makes a gap.
  - `MidiEngineHost` and the messages of `protocol.dart` are pure Dart, tested on
    the VM.
- **Isolate player** (`isolate_player.dart`, io). `MidiIsolatePlayer` runs the
  engine in a background isolate.
  - The isolate opens its output stream itself and feeds it every 5 ms, 0.1 s
    ahead, with silence when nothing plays (`MidiStreamHost`).
  - A slow frame on the UI isolate never makes an audio gap.
  - The output is a `MidiPcmStream`: `mp_audio_stream` through
    `milomedy_midi_audio_stream`, or any other.
- **Players in common.** `MidiWorkletPlayer` and `MidiIsolatePlayer` extend
  `MidiHostPlayer`.
  - It sends numbered commands and ignores the state and position events that a
    newer command has made stale.
  - It tells the position heard, moved on by its clock and wrapped in a loop.
  - It follows the meters of the tracks (`trackLevels`, `soundingKeys`,
    `onMeters`) and the speed the host reports (`onSpeed`, the steps of a
    speed trainer).
- **Offline.** `midiRenderOffline` renders a whole timeline with the same mix
  and limiter as playback. `midiWavBytes` writes 16-bit WAV.
- **Metronome.** `midiMetronomeTimeline` builds one or more measures of clicks
  on the General MIDI wood blocks. Loop it to get an endless click.
  `midiMetronomeEngine` plays it with the Dart click, with no asset.
- **Song.** `MidiSong` reads a MIDI file (format 0 or 1) through
  `tekartik_midi`.
  - Notes are paired from note on and note off. At the same tick, the note off
    comes first.
  - It keeps the other channel messages, the texts (lyrics, markers, copyright,
    track names) as bytes decoded as UTF-8 or Windows-1252, and the time and key
    signatures.
  - `MidiTempoMap` converts ticks to seconds and back, with every tempo change
    or with an SMPTE division. `barBeatAt` and `tickOf` give bars and beats.
  - `toTimeline` builds what the engine plays. It takes a track per file track
    and channel, and an instrument override per channel. Swap the result in
    with `MidiPlayer.replace` to hear it at once.

## Reverb, tune, meters and speed trainer

Added on 2026-11-17, for an app with a mixer per channel. Every player has them
(`MidiTransport`); nothing changes until they are used.

```dart
// player: a MidiHostPlayer (MidiWorkletPlayer, MidiIsolatePlayer or
// midiCreatePlayer), one track per channel, each a dry SoundFont synth
// (MidiSynthSpec(soundFont: 'gm', effects: false)).
var timeline = song.toTimeline(trackOf: (_, channel) => channel);
player.load(timeline);

// The shared reverb: a send per track, 0 by default. The engine does not
// follow the CC 91 of the file: midiReverbSends reads it (40 when none).
var sends = midiReverbSends(timeline, trackCount: 16);
for (var (track, send) in sends.indexed) {
  player.setReverb(track, send);
}
player.reverbLevel = 1; // the master level, 1 by default

// A4 at 442 Hz: about +7.85 cents, the percussion channel stays as it is.
player.tuneCents = 7.85;

// From 60 % to 100 % by 5 % at each pass of the loop.
player
  ..setLoop(8, 16)
  ..setSpeedTrainer(from: 0.6, to: 1, step: 0.05);
player.onSpeed.listen((speed) => print('speed $speed'));

// The meters (hosted players), about 30 times a second while playing.
player.onMeters.listen((meters) {
  print('${meters.levels} ${meters.keys}');
});
```

- **Reverb.** `MidiReverb` is the reverb of dart_melty_soundfont (Freeverb),
  ported to the engine with its credit: the same filters, sample for sample. A
  track sends to it after its volume (a muted track sends nothing), from 0 to 1.
  At 40 / 127, a dry SoundFont track sounds as a synth with its own reverb
  while its notes hold (melty stops feeding its reverb near the end of a
  release; the bus does not). `MidiStereoMixdown` (the hosts), `MidiStreamSink`
  (`MidiPlayer` on a raw stream) and `midiRenderOffline` mix it;
  `MidiWebAudioSink` plays dry. The bus costs nothing while nothing is sent to
  it and its tail is over. A pause or a stop cuts the tail, the end of a song
  waits for it.
- **Tune.** The engine sends RPN 1 (CC 101 = 0, CC 100 = 1, CC 6 and CC 38,
  8192 + cents × 8192 / 100) to each melodic channel of the timeline, then
  selects again the RPN the timeline had selected. It does so after each seek
  and loop pass too, because the reset of the controllers of the chase resets
  the tuning. A fine tuning set by the file gets the sum. The SoundFont synth
  hears it at once; `DartSynth` takes it as a frequency factor of
  2^(cents / 1200), from its next notes. Nothing is sent until it is set.
- **Meters.** The host reports, with each position event (`sampleRate / 30`
  frames apart: 29 a second at 44.1 kHz), the peak of each track since the
  previous one (a `Float32List`, after its volume) and the keys sounding (an
  `Int32List` of `track * 128 + key`: the notes started and not released,
  transposed). `MidiHostPlayer.trackLevels`, `soundingKeys` and `meters` hold
  the last ones, `onMeters` streams them; they go silent after a pause or a
  stop. The isolate host sends them once heard, 0.1 s after rendering; the
  worklet within the output latency.
- **Speed trainer.** `setSpeedTrainer(from:, to:, step:, everyPasses:)` sets
  the speed to `from` at once. Each time the loop starts again (every
  `everyPasses` passes), the engine takes a step toward `to`, from the frame of
  the loop start, whatever the block size. The position events carry the
  speed, so `speed` follows on the page and `onSpeed` tells each step. Setting
  the speed stops the trainer, as `clearSpeedTrainer()` does. No loop, no step.

Speed on 2026-11-17, on a Linux x64 desktop (other work running): `pop.mid`
(110 s) with GeneralUser GS 2.0.3, one track per channel, blocks of 128 frames,
`tool/benchmark.dart` of `milomedy_midi_synth_sf2`:

| Build | 16 synths with their effects | 16 dry synths | 16 dry synths + the shared reverb |
|---|---|---|---|
| VM (JIT) | 15.3x | 65.9x | 51.7x |
| AOT | 15.5x | 76.5x | 56.5x |
| dart2js (Chrome, the worklet) | 9.1x | 35.8x | 33.4x |
| dart2wasm (Chrome) | 2.1x | 10.9x | 8.9x |

In the worklet (dart2js), a block of 128 frames of the 16 tracks and the bus
takes about 0.09 ms of its 2.9 ms. The reverb alone renders 110 s in 0.26 s on
the VM.

## The AudioWorklet module

The worklet module is built from Dart by a setup step, with
[tekartik_web_worker_build](https://github.com/tekartik/app_build.dart/tree/main/packages/web_worker_build):

```
dart run milomedy_midi_engine:setup_web_worklet [--dir web] [--force] [--verbose]
```

- It compiles the worklet with dart2js in
  `.dart_tool/milomedy_midi_engine/web_worklet/`, and writes `web/midi_worklet.js`
  next to the page.
- It builds again only when the Dart SDK or a package of the worklet changed
  (the engine, the synths and their dependencies: their versions, and a hash of
  the sources of a path package), as recorded in `meta.json` next to the
  build. Otherwise it only copies the cached build.
- An app can call it from its own tool in one line, `tool/dev_build_setup.dart`
  being run by `run_ci` (dev_build >= 1.1.16) before the tests and the build:

```dart
import 'package:milomedy_midi_engine/setup.dart';

Future<void> main() => setupMidiWebWorklet();
```

Then on the page, after a user gesture:

```dart
var player = await MidiWorkletPlayer.create(synths: [MidiSynthSpec.metronome]);
var timeline = midiMetronomeTimeline(bpm: 100);
player
  ..load(timeline)
  ..setLoop(timeline.start, timeline.end);
await player.play();
```

## SoundFont tracks

A track whose spec has a `soundFont` id (`MidiSynthSpec(soundFont: 'gm')`) stays
silent until `loadSoundFont('gm', bytes)` sends the SoundFont to the host. The
engine itself does not know SoundFonts, so a metronome does not pay for them:
`milomedy_midi_synth_sf2` registers its synth where the host runs.

- **AudioWorklet:** `setup_web_worklet` registers it in the worklet when the app
  depends on `milomedy_midi_synth_sf2`.
- **Isolate:** pass `midiSoundFontRegister` as the `setup` of
  `MidiIsolatePlayer.spawn`.

`midi_render`, the CLI that renders a MIDI file to WAV, moved to
`milomedy_midi_synth_sf2`, with a `--soundfont` option.

## Examples

- `dart run example/render_wav.dart` writes `.local/metronome.wav` and an
  accordion tune to `.local/tune.wav`.
- `example/worklet_web`: a metronome and a MIDI file player on the AudioWorklet
  player. Run `dart run tool/setup_web_worklet.dart` once to build its
  `midi_worklet.js`, then serve it like the metronome page below, at
  `http://localhost:8080/worklet_web/`.
- `example/metronome_web`: a metronome page. Serve it with
  `dart run build_runner serve example:8080`, then open
  `http://localhost:8080/metronome_web/`. Compiled with `dart compile js -O2`,
  it weighs 100 KB (32 KB gzipped).

```dart
var sink = MidiWebAudioSink();
var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: sink.sampleRate));
var timeline = midiMetronomeTimeline(bpm: 100, beats: 3);
player
  ..load(timeline)
  ..setLoop(timeline.start, timeline.end);
await player.play(); // after a user gesture
```
