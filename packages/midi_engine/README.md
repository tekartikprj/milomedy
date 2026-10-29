# tekartik_midi_engine

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
  tekartik_midi_engine:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_engine
```

## midi_render

Renders a MIDI file to WAV. Until the SoundFont synth exists, every program
plays the accordion reed and the percussion channel plays the click.

```
dart run tekartik_midi_engine:midi_render [-o out.wav] [--rate 44100] [--speed 1] [--transpose 0] song.mid
```

## Examples

- `dart run example/render_wav.dart` writes `.local/metronome.wav` and an
  accordion tune to `.local/tune.wav`.
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
