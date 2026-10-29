---
name: tekartik-raw-audio-output
description: >-
  Use when generating, buffering or playing raw PCM16 audio through the
  tekartik_raw_audio abstraction: RawAudioData (fromInt16List,
  fromChannelsBytes, channelsBytes, frameCount, subFrames),
  RawAudioManager.createOutput, RawAudioOutput (feed, play, stop, options,
  feedOptions), RawAudioOutputOptions (sampleRate, channelCount),
  RawAudioOutputFeedOptions (feedThreshold, onFeed callback), the in-memory
  RawAudioManagerMemory/RawAudioOutputMemory for tests, the
  pcm16GenerateSineWaveAudioData/pcm16GenerateExampleAudioData generators,
  and RawAudioManagerMixin/RawAudioOutputMixin when writing a backend (the
  flutter pcm_sound, wav and web backends live in sibling packages).
---

# Raw audio output (tekartik_raw_audio)

`tekartik_raw_audio` defines a tiny backend-neutral API for pushing 16 bit PCM
frames to an audio output: a `RawAudioManager` creates `RawAudioOutput`s and
you `feed` them `RawAudioData`. This package ships the API, an in-memory
backend and sine generators; real backends are the sibling packages
`tekartik_raw_audio_pcm_sound` (Flutter, `flutter_pcm_sound`),
`tekartik_raw_audio_wav` (wav files) and `tekartik_raw_audio_web`.

## Guidelines

* Dependency (git, `publish_to: none`):
  ```yaml
  dependencies:
    tekartik_raw_audio:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/raw_audio
  ```
  Backends use the same `url` with `path: packages/raw_audio_pcm_sound`
  (`rawAudioManagerPcmSound`), `packages/raw_audio_wav`
  (`RawAudioManagerWav`, `RawAudioOutputWav.wav`) or
  `packages/raw_audio_web`; they re-export `raw_audio.dart`.
* Imports: `package:tekartik_raw_audio/raw_audio.dart` for `RawAudioData`,
  `RawAudioManager`, `RawAudioOutput`, `RawAudioOutputOptions`,
  `RawAudioOutputFeedOptions`, `RawAudioOnFeedCallback` (it also re-exports
  `Uint8List`); `raw_audio_memory.dart` for `RawAudioManagerMemory` and
  `RawAudioOutputMemory`; `generator.dart` for
  `pcm16GenerateSineWaveAudioData` and `pcm16GenerateExampleAudioData`;
  `raw_audio_mixin.dart` for `RawAudioManagerMixin` and
  `RawAudioOutputMixin`. The format enum and the default constants are not
  exported: the only format is signed 16 bit PCM and
  `RawAudioOutputOptions()` defaults to 44100 Hz, 2 channels.
* `RawAudioData` is planar: `channelsBytes` holds one `Uint8List` per
  channel, 2 bytes per frame, and `frameCount` is
  `channelsBytes.first.length ~/ 2`. Build it with
  `RawAudioData.fromChannelsBytes(channelsBytes: [left, right])` or, for a
  single channel, `RawAudioData.fromInt16List(samples)` (packs with
  `ByteData.setInt16`, big-endian by default). `subFrames(start, end)`
  copies a frame range (`end` is clamped to `frameCount`).
* Backends pass the bytes through untouched (`pcm_sound` hands
  `channelsBytes.first` to the platform, `wav` decodes the bytes as
  little-endian pcm16). When byte order matters, build the bytes yourself
  with `ByteData.setInt16(offset, value, Endian.little)` and
  `fromChannelsBytes`.
* Channel counts must agree: `RawAudioOutputMemory.feed` reads
  `data.channelsBytes[i]` for each of the `options.channelCount` channels and
  throws `RangeError` when mono data is fed to a stereo output. The
  generators produce mono data, so create their outputs with
  `channelCount: 1`.
* Output lifecycle: `manager.createOutput(options: RawAudioOutputOptions(
  sampleRate: 44100, channelCount: 1), feedOptions: ...)`, then
  `await output.play()`, `await output.feed(data)` as often as needed,
  `await output.stop()`. `feed` appends: the memory backend concatenates
  everything into `output.channelsBytes`. `play` and `stop` are no-ops in the
  memory backend and in the mixin defaults.
* Pull-style streaming: pass `RawAudioOutputFeedOptions(feedThreshold:
  frames, onFeed: (output, remainingFrames) { ... })`. A buffering backend
  (pcm_sound) calls `onFeed` when its queue drops below `feedThreshold`
  frames; feed the next chunk from the callback (`data.subFrames(...)`). The
  memory backend never calls it.
* Writing a backend: `class MyManager with RawAudioManagerMixin implements
  RawAudioManager` overriding `createOutput`, and `class MyOutput with
  RawAudioOutputMixin implements RawAudioOutput` overriding `options`,
  `feedOptions` and `feed` (the mixin getters throw `UnimplementedError`,
  `play`/`stop` do nothing). Program against `RawAudioManager` and
  `RawAudioOutput` so the same code runs on every backend.
* Tests: `dart test`; use `RawAudioManagerMemory` and inspect
  `output.channelsBytes` (see `test/raw_audio_memory_test.dart`).

## Examples

### Generate a scale into an in-memory output

```dart
import 'package:tekartik_raw_audio/generator.dart';
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';

Future<void> main() async {
  var manager = RawAudioManagerMemory();
  // Generators are mono: one channel.
  var output = manager.createOutput(
    options: RawAudioOutputOptions(sampleRate: 44100, channelCount: 1),
  );
  await output.play();
  await output.feed(pcm16GenerateExampleAudioData(noteDuration: 0.25));
  await output.feed(
    pcm16GenerateSineWaveAudioData(periods: 440, freq: 440, volume: 0.3),
  );
  await output.stop();
  print('${output.channelsBytes.first.length ~/ 2} frames buffered');
}
```

### Stereo data from int samples, streamed in chunks through onFeed

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:tekartik_raw_audio/raw_audio.dart';

/// Little endian 16 bit bytes for one channel.
Uint8List pcm16Bytes(List<int> samples) {
  var bytes = Uint8List(samples.length * 2);
  var data = ByteData.view(bytes.buffer);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

Future<void> stream(
  RawAudioManager manager,
  List<int> left,
  List<int> right,
) async {
  var all = RawAudioData.fromChannelsBytes(
    channelsBytes: [pcm16Bytes(left), pcm16Bytes(right)],
  );
  const chunkFrames = 4096;
  var position = 0;
  var output = manager.createOutput(
    options: RawAudioOutputOptions(sampleRate: 44100, channelCount: 2),
    feedOptions: RawAudioOutputFeedOptions(
      feedThreshold: chunkFrames,
      onFeed: (output, remainingFrames) {
        // Called by buffering backends when fewer than chunkFrames remain.
        if (position < all.frameCount) {
          var end = position + chunkFrames;
          unawaited(output.feed(all.subFrames(position, end)));
          position = end;
        }
      },
    ),
  );
  await output.play();
  // Prime the buffer, the backend then pulls through onFeed.
  await output.feed(all.subFrames(0, chunkFrames));
  position = chunkFrames;
}
```

### A logging backend built on the mixins

```dart
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_mixin.dart';

class LogRawAudioManager
    with RawAudioManagerMixin
    implements RawAudioManager {
  @override
  RawAudioOutput createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  }) => LogRawAudioOutput(options: options, feedOptions: feedOptions);
}

class LogRawAudioOutput with RawAudioOutputMixin implements RawAudioOutput {
  @override
  final RawAudioOutputOptions options;
  @override
  final RawAudioOutputFeedOptions? feedOptions;
  var fedFrames = 0;

  LogRawAudioOutput({required this.options, this.feedOptions});

  @override
  Future<void> feed(RawAudioData data) async {
    fedFrames += data.frameCount;
    print(
      'feed ${data.frameCount} frames, ${data.channelsBytes.length} '
      'channel(s), total $fedFrames',
    );
  }
  // play() and stop() keep the mixin no-op defaults.
}
```

### Unit test with the memory backend

```dart
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';
import 'package:test/test.dart';

void main() {
  test('feed appends', () async {
    var output = RawAudioManagerMemory().createOutput(
      options: RawAudioOutputOptions(sampleRate: 8000, channelCount: 1),
    );
    await output.feed(RawAudioData.fromInt16List([1, -1]));
    await output.feed(RawAudioData.fromInt16List([2]));
    // fromInt16List packs big-endian.
    expect(output.channelsBytes.first, [0, 1, 255, 255, 0, 2]);
  });
}
```
