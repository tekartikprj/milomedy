# milomedy_midi_engine

A MIDI engine in pure Dart (VM, dart2js, dart2wasm), taken from accordelio's
sound engine and generalized from its four parts to tracks and MIDI channels.

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
  - `replace` swaps the timeline in place (an edit).
- **Mixer.** `MidiMixer` sets the volume, pan, mute and solo of each track,
  then a master gain and a limiter. The pan behaves like a Web Audio
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

## Setup

```yaml
dependencies:
  milomedy_midi_engine:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_engine
```

## The AudioWorklet module

The worklet module is built from Dart by a setup step, as `sqflite_common_ffi_web`
builds its shared worker:

```
dart run milomedy_midi_engine:setup_web_worklet [--dir web] [--force] [--verbose]
```

- It compiles the worklet with dart2js in
  `.dart_tool/milomedy_midi_engine/web_worklet/`, and writes `web/midi_worklet.js`
  next to the page.
- It builds again only when the package version, the sources of the engine and
  the synths, the `web` package or the Dart SDK changed. Otherwise it only copies
  the cached build.
- An app can call it from its own tool in one line:

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
