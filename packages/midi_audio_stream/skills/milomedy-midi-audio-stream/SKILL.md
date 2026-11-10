---
name: milomedy-midi-audio-stream
description: >-
  Use when playing the milomedy MIDI engine in a Flutter app with
  milomedy_midi_audio_stream: midiCreatePlayer (the isolate player on
  mp_audio_stream on Android, iOS, Linux, macOS and Windows, the AudioWorklet
  player on the web), its workletUrl and isolateSetup (midiSoundFontRegister
  for SoundFont tracks), setup_web_worklet for the web build,
  MidiMpAudioStream and midiMpAudioStreamOpener, one player at a time, and
  testing without the native library.
---

# MIDI engine in Flutter (milomedy_midi_audio_stream)

`midiCreatePlayer(synths:)` returns a `MidiHostPlayer` of
`milomedy_midi_engine` that plays on every Flutter platform: a background
isolate feeding `mp_audio_stream` (miniaudio bundled, nothing to install)
on Android, iOS and the desktops, an AudioWorklet on the web. The player API
(`load`, `setLoop`, `play`, `pause`, `stop`, `seek`, `speed`, `transpose`,
the mixer, `position`, `onState`, `onError`, `close`) is the engine's: see
the `milomedy-midi-engine` skill.

## Guidelines

* Dependencies (git, public repo, not on pub.dev): this package and
  `milomedy_midi_engine` (for `MidiSynthSpec`, `MidiTimeline`,
  `midiMetronomeTimeline`...):
  ```yaml
  dependencies:
    milomedy_midi_audio_stream:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_audio_stream
    milomedy_midi_engine:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_engine
  ```
* Imports: `package:milomedy_midi_audio_stream/midi_audio_stream.dart`
  (`midiCreatePlayer`, and on io `MidiMpAudioStream`,
  `midiMpAudioStreamOpener`) and `package:milomedy_midi_engine/midi_engine.dart`.
* One synth per track: `synths: [MidiSynthSpec(instrument: ...),
  MidiSynthSpec.metronome]`, a note's `track` picks its synth.
* Web: run `dart run milomedy_midi_engine:setup_web_worklet` in the app
  (it writes `web/midi_worklet.js`, the default `workletUrl`), again after an
  upgrade; create the player from a user gesture.
* SoundFonts (`milomedy_midi_synth_sf2`): `midiCreatePlayer(synths: [const
  MidiSynthSpec(soundFont: 'gm')], isolateSetup: midiSoundFontRegister)`,
  then `await player.loadSoundFont('gm', bytes)` (the track is silent
  before). On the web `setup_web_worklet` registers it in the worklet when
  the app depends on `milomedy_midi_synth_sf2`; `isolateSetup` is ignored.
* `isolateSetup` is sent to the isolate: a top-level function (or a closure
  of sendable values only).
* One player at a time on io (mp_audio_stream has one native stream for the
  app): `await old.close()` before `midiCreatePlayer` of the next one;
  closing the old one after would stop the device of the new one.
* The frames are pushed 0.1 s ahead: `position` is what is heard, a change
  (speed, transpose, a seek) is heard within that.
* `flutter test` has no native mp_audio_stream: `midiCreatePlayer` fails
  with a `StateError`. Test the logic with the engine (a `MidiPlayer` on a
  `MidiSilentSink`, or `MidiIsolatePlayer.spawn` with a capturing
  `MidiPcmStream`); play for real with the example's integration test on a
  device (`flutter test integration_test/play_test.dart -d macos`).

## Examples

### A metronome screen

```dart
import 'package:flutter/widgets.dart';
import 'package:milomedy_midi_audio_stream/midi_audio_stream.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

class Metronome extends StatefulWidget {
  const Metronome({super.key});

  @override
  State<Metronome> createState() => _MetronomeState();
}

class _MetronomeState extends State<Metronome> {
  MidiHostPlayer? _player;

  /// Called from a button: the web needs a user gesture.
  Future<void> _start(double bpm) async {
    var player = _player ??= await midiCreatePlayer(
      synths: [MidiSynthSpec.metronome],
    );
    var timeline = midiMetronomeTimeline(bpm: bpm);
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end);
    await player.play();
  }

  @override
  void dispose() {
    _player?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _start(100),
    child: const Text('Start at 100 bpm'),
  );
}
```
