# milomedy_midi_audio_stream

The MIDI engine of `milomedy_midi_engine` on every Flutter platform:

- **Android, iOS, Linux, macOS and Windows.** A background isolate runs the
  engine and feeds [`mp_audio_stream`](https://pub.dev/packages/mp_audio_stream),
  which bundles miniaudio, so there is no system library to install. The frames
  are pushed 0.1 s ahead, so a slow frame on the UI isolate is never a gap.
- **The web.** The AudioWorklet player: the engine runs on the audio thread.

## Setup

```yaml
dependencies:
  milomedy_midi_audio_stream:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_audio_stream
```

For the web, build the AudioWorklet module into `web/`, again after an upgrade.
It is only built again when something changed:

```
dart run milomedy_midi_engine:setup_web_worklet
```

## Use

```dart
var player = await midiCreatePlayer(synths: [MidiSynthSpec.metronome]);
var timeline = midiMetronomeTimeline(bpm: 100);
player
  ..load(timeline)
  ..setLoop(timeline.start, timeline.end);
await player.play();
```

On the web, create the player after a user gesture.

- `mp_audio_stream` has a single native stream, so open one player at a time.
- `MidiMpAudioStream` is the `MidiPcmStream` behind the isolate player, for other
  uses.

## Example

`example/` plays a metronome and a waltz on accordion reeds, with tempo, speed and
transpose. It runs on macOS, Linux, Windows and the web.
`integration_test/play_test.dart` plays on the device:

```
cd example
flutter test integration_test/play_test.dart -d macos
```
