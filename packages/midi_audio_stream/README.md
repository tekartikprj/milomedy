# milomedy_midi_audio_stream

The MIDI engine of `milomedy_midi_engine` playing in a Flutter app, on every
platform, from one call, `midiCreatePlayer`:

- **Android, iOS, Linux, macOS and Windows.** A background isolate runs the
  engine and feeds [`mp_audio_stream`](https://pub.dev/packages/mp_audio_stream),
  which bundles miniaudio, so there is no system library to install. The frames
  are pushed 0.1 s ahead, so a slow frame on the UI isolate is never a gap.
- **The web.** The AudioWorklet player: the engine runs on the audio thread.

## Getting started

Not on pub.dev, git dependencies (the engine too, for the timelines and the
synth specs):

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

For the web, build the AudioWorklet module into `web/`, again after an upgrade
(it is only built again when something changed):

```
dart run milomedy_midi_engine:setup_web_worklet
```

Play a metronome at 100 bpm, in a loop:

```dart
import 'package:milomedy_midi_audio_stream/midi_audio_stream.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

/// On the web, call it from a user gesture (a button).
Future<MidiHostPlayer> playMetronome() async {
  var player = await midiCreatePlayer(synths: [MidiSynthSpec.metronome]);
  player.onError.listen((message) => print('player error: $message'));
  var timeline = midiMetronomeTimeline(bpm: 100);
  player
    ..load(timeline)
    ..setLoop(timeline.start, timeline.end);
  await player.play();
  return player; // pause(), stop(), seek(), speed, transpose... close()
}
```

## SoundFonts

For SoundFont tracks (`milomedy_midi_synth_sf2`), pass
`isolateSetup: midiSoundFontRegister`. On the web, `setup_web_worklet` puts the
SoundFont synth in the worklet when the app depends on that package. Then load
the SoundFont with `await player.loadSoundFont(id, bytes)`; a
`MidiSynthSpec(soundFont: id)` track is silent until then.

## Good to know

- `mp_audio_stream` has a single native stream for the whole app: one
  player at a time. Close the old player before creating the next one;
  closing it after would stop the device the new one plays on.
- On the web, create the player after a user gesture (the browser keeps the
  audio suspended otherwise).
- `MidiMpAudioStream` is the `MidiPcmStream` behind the isolate player
  (`MidiIsolatePlayer.spawn(openStream: midiMpAudioStreamOpener)`), for
  other uses; it is not available on the web.
- `flutter test` has no native library: `midiCreatePlayer` then fails with a
  `StateError`; test the player logic with the engine's silent sink.

## Example

`example/` plays a metronome and a waltz on accordion reeds, with tempo, speed and
transpose. It runs on macOS, Linux, Windows and the web.
`integration_test/play_test.dart` plays on the device:

```
cd example
flutter test integration_test/play_test.dart -d macos
```
