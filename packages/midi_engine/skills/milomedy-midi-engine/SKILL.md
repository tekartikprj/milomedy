---
name: milomedy-midi-engine
description: >-
  Use when playing, rendering or reading MIDI in Dart with
  milomedy_midi_engine: MidiTimeline (MidiTimelineNote, MidiTimelineMessage),
  MidiEngine (load, render, seek, setLoop, speed, transpose, tuneCents,
  speedTrainer, replace),
  MidiPlayer with a MidiAudioSink (MidiWebAudioSink, MidiStreamSink,
  MidiSilentSink), MidiWorkletPlayer (web AudioWorklet, setup_web_worklet),
  MidiIsolatePlayer (io), MidiHostPlayer and MidiSynthSpec, the mixer
  (volume, pan, mute, solo, setReverb and the shared MidiReverb,
  midiReverbSends, setChorus and the shared MidiChorus, midiChorusSends), the tuning (tuneCents, RPN 1), the speed trainer of a
  loop (setSpeedTrainer, MidiSpeedTrainer, onSpeed), the meters of the
  tracks (trackLevels, soundingKeys, onMeters, MidiTrackMeters),
  midiRenderOffline and midiWavBytes, the
  metronome (midiMetronomeTimeline, midiMetronomeEngine), and MidiSong
  (fromBytes, toTimeline, MidiTempoMap, barBeatAt, tickOf, texts and lyrics).
---

# MIDI engine (milomedy_midi_engine)

A pure Dart MIDI engine: a `MidiTimeline` (notes and channel messages in
seconds, on tracks) is played by a `MidiEngine`, one synth per track
(`milomedy_midi_synth`), each event at its exact frame. Players keep an
output fed and tell the position; `MidiSong` reads a MIDI file into a
timeline.

## Guidelines

* Dependency (git, public repo, not on pub.dev):
  ```yaml
  dependencies:
    milomedy_midi_engine:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_engine
  ```
  Add `milomedy_midi_synth` (same url, `path: packages/midi_synth`) to build
  `DartSynth`s yourself, `milomedy_midi_synth_sf2` for SoundFonts,
  `milomedy_midi_audio_stream` for the io output of the isolate player.
* Libraries: `midi_engine.dart` (every platform: timeline, engine, mixer,
  `MidiPlayer`, sinks interface, offline, WAV, metronome, song, host and
  protocol), `web_audio.dart` (web: `MidiWebAudioSink`), `web_worklet.dart`
  (web: `MidiWorkletPlayer`), `isolate_player.dart` (io:
  `MidiIsolatePlayer`), `setup.dart` (io tool: builds the worklet module).
* Pick a player: `MidiPlayer(sink, engine)` renders on the calling isolate a
  little ahead of the output (simple, tests, a page with little else to do);
  `MidiWorkletPlayer.create(synths: [...])` runs the engine on the web audio
  thread (no gap when the page is busy; build its module with
  `dart run milomedy_midi_engine:setup_web_worklet`, it is loaded from
  `midi_worklet.js` next to the page); `MidiIsolatePlayer.spawn(synths:,
  openStream:)` runs it in an isolate on io. All implement `MidiTransport`:
  `load`, `replace` (an edit heard at once), `play`, `pause`, `stop`,
  `seek`, `setLoop`, `speed`, `transpose`, `setVolume/Pan/Mute/Solo`,
  `position`, `state`/`onState`, `close`.
* Host players take `MidiSynthSpec`s (data, sent to where the engine runs):
  `MidiSynthSpec(instrument: MidiInstrumentIds.reed, register: 'musette',
  percussion: MidiInstrumentIds.click)`, `MidiSynthSpec.metronome`, or
  `MidiSynthSpec(soundFont: 'gm')`, silent until
  `player.loadSoundFont('gm', bytes)` (the SoundFont support must be
  registered where the engine runs: see `milomedy_midi_synth_sf2`).
  `transfer: true` moves the bytes to the AudioWorklet instead of copying
  them (empty afterwards): for a large SoundFont read for this call alone.
* One sample rate everywhere: `MidiEngine` checks its synths, `MidiPlayer`
  its sink (`ArgumentError`). On the web use the sink's
  (`MidiWebAudioSink().sampleRate`). Timeline events on a track without a
  synth are ignored.
* Web: an AudioContext starts suspended; `play()` resumes it and must follow
  a user gesture (a click handler).
* `MidiSong.fromBytes(bytes)` (format 0 or 1; format 2 is an
  `UnsupportedError`, a bad file a `FormatException`): `notes` paired at
  their ticks, `messages`, `texts` (`lyrics`, `markers`, `trackNames`,
  `copyright`, UTF-8 or Windows-1252), `timeSignatures`, `keySignatures`,
  `tempoMap`, `duration`, `barBeatAt(tick)`, `tickOf(bar, beat)`,
  `tickAt(seconds)`. `toTimeline(trackOf: (fileTrack, channel) => track,
  programs: {channel: program})` builds what the engine plays (track 0 by
  default). A tempo of 0 and a time signature of 0 beats are ignored.
* Offline: `midiRenderOffline(engine, timeline)` gives interleaved stereo
  floats with the same mix and limiter as playback (the whole song in
  memory), `midiWavBytes(samples, sampleRate:)` a 16 bit WAV.
* Metronome: `midiMetronomeTimeline(bpm:, beats:, measures:)` on the
  percussion channel, loop it with `setLoop(timeline.start, timeline.end)`
  for an endless click; `midiMetronomeEngine(sampleRate:)` plays it with no
  asset.
* Shared reverb: `player.setReverb(track, send)` (0 to 1, 0 by default,
  after the track volume) and `player.reverbLevel` (1 by default). One
  Freeverb (`MidiReverb`, melty's, sample for sample) on the mix of the
  hosts, of `MidiStreamSink` and of `midiRenderOffline` (from
  `MidiMixer.tracks[i].reverb`); `MidiWebAudioSink` plays dry. Give one dry
  SoundFont synth per channel (`MidiSynthSpec(soundFont: id, effects:
  false)`) and send them to the bus: 16 synths with their own effects are 4
  times slower. The engine does not follow CC 91: set the sends from
  `midiReverbSends(timeline, trackCount: 16)` (40 / 127 when the file has
  none). A pause cuts the tail; the end waits for it.
* Shared chorus, the same way: `player.setChorus(track, send)` (after the
  volume and the pan) and `player.chorusLevel`; `MidiChorus` is melty's
  chorus (2 ms swept by 1.9 ms at 0.4 Hz). Set the sends from
  `midiChorusSends(timeline, trackCount: 16)` (CC 93, 0 when none).
* Tune: `player.tuneCents = 7.85` (A4 at 442 Hz; -100 to 100, an
  `ArgumentError` otherwise). RPN 1 to every melodic channel of the timeline
  (never the percussion channel), sent again after each seek and loop pass
  (the chase resets the controllers, the tuning too); a file's own RPN 1
  gets the sum. The SoundFont synth hears it at once, `DartSynth` from its
  next notes (`DartTunableInstrument`: the reeds, the click).
* Speed trainer: `player.setSpeedTrainer(from: 0.6, to: 1, step: 0.05,
  everyPasses: 1)` needs a loop (`setLoop`); the speed is `from` at once,
  then steps toward `to` at the frame each pass starts. `speed` follows the
  host's reports (`onSpeed` on a `MidiHostPlayer`); setting `speed` or
  `clearSpeedTrainer()` stops it. `MidiSpeedTrainer.speedAfter(passes)`.
* Meters (hosted players): `player.trackLevels` (peak per track since the
  last report, after its volume), `player.soundingKeys` (a set of transposed
  keys per track, notes started and not released), `player.meters` and
  `onMeters` (a `MidiTrackMeters`), about 30 times a second while playing
  (`MidiEngineHost.reportFrames`, `sampleRate / 30` by default), silent once
  paused or stopped. The isolate host sends them when heard.
* Tests: `MidiSilentSink(sampleRate:, clock: () => t, keep: true)` with a
  hand driven clock and `player.pump()`, or `engine.render(frames)` directly
  (`MidiRenderBlock.left/right` per track). `MidiEngineHost` and the
  protocol run on the VM (the worklet and the isolate are thin shells).

## Examples

### Render a MIDI file to WAV (io)

```dart
import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';

Future<void> main(List<String> args) async {
  const sampleRate = 44100;
  var song = MidiSong.fromBytes(await File(args.first).readAsBytes());
  // Track 0: the reeds for every program, track 1: the drums.
  var engine = MidiEngine(
    sampleRate: sampleRate,
    synths: [
      DartSynth(sampleRate: sampleRate, instrument: ReedInstrument.treble()),
      DartSynth(sampleRate: sampleRate, percussion: const ClickInstrument()),
    ],
  );
  var timeline = song.toTimeline(
    trackOf: (_, channel) => channel == midiPercussionChannel ? 1 : 0,
  );
  var samples = midiRenderOffline(engine, timeline);
  await File(
    'out.wav',
  ).writeAsBytes(midiWavBytes(samples, sampleRate: sampleRate));
  print('${song.duration.toStringAsFixed(1)} s, ${song.notes.length} notes');
}
```

### A metronome on a web page (AudioWorklet)

```dart
import 'dart:js_interop';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';
import 'package:web/web.dart' as web;

MidiWorkletPlayer? player;

web.HTMLElement _element(String id) =>
    web.document.querySelector('#$id') as web.HTMLElement;

void main() {
  _element('play').onclick = (web.Event _) {
    _play();
  }.toJS;
  _element('stop').onclick = (web.Event _) {
    player?.stop();
  }.toJS;
  // The position heard, in seconds.
  void show(JSNumber _) {
    var text = player?.position.toStringAsFixed(2) ?? '';
    _element('position').textContent = text;
    web.window.requestAnimationFrame(show.toJS);
  }

  web.window.requestAnimationFrame(show.toJS);
}

Future<void> _play() async {
  // Created after a user gesture; midi_worklet.js is next to the page.
  var metronome = player ??= await MidiWorkletPlayer.create(
    synths: [MidiSynthSpec.metronome],
  );
  var timeline = midiMetronomeTimeline(bpm: 100);
  metronome
    ..load(timeline)
    ..setLoop(timeline.start, timeline.end);
  await metronome.play();
}
```

### Test a player without a sound card

```dart
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:test/test.dart';

void main() {
  test('plays, then stops at the end', () async {
    var now = 0.0;
    var sink = MidiSilentSink(sampleRate: 8000, clock: () => now);
    var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: 8000));
    player.load(midiMetronomeTimeline(bpm: 120, beats: 2)); // 1 s
    await player.play();
    for (; now < 2; now += 0.02) {
      player.pump();
    }
    expect(player.state, MidiPlayerState.stopped);
    await player.close();
  });
}
```
