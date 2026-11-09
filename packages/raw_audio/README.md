# tekartik_raw_audio

A small backend neutral API to push raw audio (PCM, signed 16 bit,
little-endian) to an output: a `RawAudioManager` creates `RawAudioOutput`s,
you `feed` them `RawAudioData`. This package has the API, an in-memory backend
(tests) and sine generators. Pure Dart, every platform.

Backends, in the same repo: `packages/raw_audio_pcm_sound` (Flutter, the
speaker, through `flutter_pcm_sound`) and `packages/raw_audio_wav` (a wav
file). They re-export this API.

## Getting started

Not on pub.dev, a git dependency:

```yaml
dependencies:
  tekartik_raw_audio:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/raw_audio
```

```dart
import 'package:tekartik_raw_audio/generator.dart';
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';

Future<void> main() async {
  // Any backend: the memory one here, a speaker or a wav file in the others.
  RawAudioManager manager = RawAudioManagerMemory();
  // The generators give one channel: a mono output.
  var output = manager.createOutput(
    options: RawAudioOutputOptions(sampleRate: 44100, channelCount: 1),
  );
  await output.play();
  await output.feed(pcm16GenerateExampleAudioData()); // a scale, 4 s
  await output.stop();
}
```

## The data

* `RawAudioData.fromInt16List(samples)`: one channel from int samples
  (`-32768..32767`).
* `RawAudioData.fromChannelsBytes(channelsBytes: [left, right])`: one
  `Uint8List` per channel (planar, not interleaved), 2 bytes a frame,
  little-endian.
* `frameCount`, `subFrames(start, end)` (a copy of a frame range).

## Common mistakes

* `RawAudioOutputOptions()` defaults to 2 channels: feeding it mono data (the
  generators, `fromInt16List`) throws a `RangeError` in the memory backend;
  give `channelCount: 1`.
* Bytes built by hand must be little-endian
  (`ByteData.setInt16(offset, value, Endian.little)`).
* `feed` appends: chunk long sounds and feed them from
  `RawAudioOutputFeedOptions.onFeed` (called by buffering backends).

Agent skill: [tekartik-raw-audio-output](skills/tekartik-raw-audio-output/SKILL.md).
