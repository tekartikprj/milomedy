---
name: tekartik-raw-audio-pcm-sound-setup
description: >-
  Use when playing realtime PCM16 audio from a Flutter app with
  tekartik_raw_audio_pcm_sound: the rawAudioManagerPcmSound global,
  RawAudioManagerPcmSound (createOutput, stopAll), feeding RawAudioData built
  with fromChannelsBytes, play/stop, RawAudioOutputFeedOptions
  (feedThreshold/onFeed) pull streaming over flutter_pcm_sound, the
  package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart import, the
  android/ios/macos only platform support, the single sampleRate per app
  limitation and the little-endian byte order the platform expects.
---

# Flutter pcm_sound backend for raw audio (tekartik_raw_audio_pcm_sound)

`tekartik_raw_audio_pcm_sound` implements the `tekartik_raw_audio` output API
with [`flutter_pcm_sound`](https://pub.dev/packages/flutter_pcm_sound): the
frames you `feed` go straight to the device speakers, with a pull callback
when the platform queue runs low. It is the "real" backend of the family;
`tekartik_raw_audio_wav` (files) and the in-memory manager are the testable
ones.

## Guidelines

* Dependency (git, private repo, not on pub.dev):
  ```yaml
  dependencies:
    tekartik_raw_audio_pcm_sound:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/raw_audio_pcm_sound
  ```
  It brings `tekartik_raw_audio` (same repo, `path: packages/raw_audio`) and
  `flutter_pcm_sound`. Flutter only, and `flutter_pcm_sound` ships android,
  ios and macos implementations only: no web, no linux, no windows, and
  nothing works in a plain `dart test`. Guard the import/usage behind a
  platform check in a multi-platform app.
* One import,
  `package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart`: it
  re-exports `package:tekartik_raw_audio/raw_audio.dart` (`RawAudioData`,
  `RawAudioManager`, `RawAudioOutput`, `RawAudioOutputOptions`,
  `RawAudioOutputFeedOptions`, `Uint8List`) and adds
  `RawAudioManagerPcmSound` plus the ready-made global
  `rawAudioManagerPcmSound`. The `tekartik-raw-audio-output` skill of
  `tekartik_raw_audio` documents the shared API.
* There is no public constructor: always use the `rawAudioManagerPcmSound`
  singleton, and `manager.createOutput(options: RawAudioOutputOptions(
  sampleRate: 44100, channelCount: 1), feedOptions: ...)`. The concrete
  output type is not exported — keep your fields and parameters typed as
  `RawAudioOutput` (or `var` for a local).
* `play()` is what actually initialises the plugin (`FlutterPcmSound.setup`,
  `setFeedThreshold`, `setFeedCallback`), so `await output.play()` before
  feeding; `feed()` awaits the same initialisation, so a plain `feed` works
  too. Then feed the first chunk yourself: this backend never calls
  `FlutterPcmSound.start()`, so nothing is playing until something is queued.
* Only **one** configuration per app run: the first output that becomes ready
  calls `setup(sampleRate, channelCount)`, and creating another output with a
  different `sampleRate`/`channelCount` throws `UnsupportedError` when it
  initialises. `stopAll()` does not reset that. Two outputs with the same
  options share the one platform queue and the one (global) feed callback:
  the last one registered wins, and their audio interleaves. Create a single
  output and keep it.
* `stop()` / `stopAll()` only flip an internal flag in the current
  implementation — the calls to the plugin are commented out, so already
  queued frames keep playing. To really go silent, stop feeding (return
  early from `onFeed`) and, if you need to free the audio session, call
  `FlutterPcmSound.release()` yourself by depending on `flutter_pcm_sound`
  directly.
* Byte order: the plugin sends the bytes untouched and reads them as
  host-endian 16 bit samples — little-endian on every supported device. But
  `RawAudioData.fromInt16List(samples)` packs **big-endian**, and so do
  `pcm16GenerateSineWaveAudioData` / `pcm16GenerateExampleAudioData` from
  `package:tekartik_raw_audio/generator.dart`: fed as is they play as noise.
  Build the bytes with `ByteData.setInt16(offset, value, Endian.little)` and
  `RawAudioData.fromChannelsBytes(channelsBytes: [bytes])`, which is also
  what libraries that render into an `ArrayInt16`-style buffer already give
  you.
* Channels: `feed` only sends `data.channelsBytes.first` to the platform. Mono
  (`channelCount: 1`) is the straightforward case. For `channelCount: 2` the
  platform expects **interleaved** L/R samples in that single buffer — build
  it yourself, and remember that `RawAudioData.frameCount` and `subFrames`
  then count samples, not stereo frames (two bytes each).
* Pull streaming is the point of this backend: pass
  `RawAudioOutputFeedOptions(feedThreshold: frames, onFeed: (output,
  remainingFrames) { ... })` and feed the next chunk from the callback
  (`data.subFrames(start, end)` or freshly rendered samples). The callback
  fires once per `feed` when the queue drops below `feedThreshold` and once
  when it drains to 0, so always feed something (or explicitly stop) from it,
  otherwise the pull chain ends. Bigger `feedThreshold` = safer, more latency.
* Keep audio generation out of the widget tree: the callback runs on the UI
  isolate, so keep it short (copy an existing buffer, render a few hundred
  frames), and do heavy synthesis in an isolate.
* Testing: this package needs a device. Write your generation code against
  `RawAudioManager`/`RawAudioOutput`, unit test it with `RawAudioManagerMemory`
  (`package:tekartik_raw_audio/raw_audio_memory.dart`) or capture a file with
  `RawAudioManagerWav` (`tekartik_raw_audio_wav`), and inject
  `rawAudioManagerPcmSound` only in the app.

## Examples

### Play a buffer once

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

/// Little endian pcm16 bytes, the order the platform expects.
Uint8List pcm16LeBytes(List<int> samples) {
  var bytes = Uint8List(samples.length * 2);
  var byteData = ByteData.view(bytes.buffer);
  for (var i = 0; i < samples.length; i++) {
    byteData.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

/// A 440Hz beep of [duration].
Future<void> beep({Duration duration = const Duration(seconds: 1)}) async {
  const sampleRate = 44100;
  var frames = sampleRate * duration.inMilliseconds ~/ 1000;
  var samples = List.generate(
    frames,
    (i) => (32767 * 0.3 * math.sin(2 * math.pi * 440 * i / sampleRate)).round(),
  );
  var output = rawAudioManagerPcmSound.createOutput(
    options: RawAudioOutputOptions(sampleRate: sampleRate, channelCount: 1),
  );
  await output.play();
  await output.feed(
    RawAudioData.fromChannelsBytes(channelsBytes: [pcm16LeBytes(samples)]),
  );
}
```

### Stream a long buffer through the feed callback

```dart
import 'dart:async';

import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

/// Plays [data] (mono, little endian pcm16) chunk by chunk.
Future<RawAudioOutput> playStreamed(
  RawAudioData data, {
  int sampleRate = 44100,
  int chunkFrames = 8000,
}) async {
  var position = 0;
  var frameCount = data.frameCount;
  var output = rawAudioManagerPcmSound.createOutput(
    options: RawAudioOutputOptions(sampleRate: sampleRate, channelCount: 1),
    feedOptions: RawAudioOutputFeedOptions(
      feedThreshold: chunkFrames,
      onFeed: (output, remainingFrames) {
        if (position >= frameCount) {
          return; // Nothing left, the pull chain ends here.
        }
        var end = position + chunkFrames;
        if (end > frameCount) {
          end = frameCount;
        }
        var chunk = data.subFrames(position, end);
        position = end;
        unawaited(output.feed(chunk));
      },
    ),
  );
  await output.play();
  // Prime the queue: the backend does not start on its own.
  var end = chunkFrames > frameCount ? frameCount : chunkFrames;
  await output.feed(data.subFrames(0, end));
  position = end;
  return output;
}
```

### Wire it into a widget

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

class PlayerButton extends StatefulWidget {
  const PlayerButton({super.key});

  @override
  State<PlayerButton> createState() => _PlayerButtonState();
}

class _PlayerButtonState extends State<PlayerButton> {
  /// The concrete output type is not exported, keep the abstraction.
  RawAudioOutput? _output;

  /// Half a second of 440Hz, little endian pcm16.
  RawAudioData _tone() {
    const sampleRate = 44100;
    var bytes = Uint8List(sampleRate);
    var byteData = ByteData.view(bytes.buffer);
    for (var i = 0; i < sampleRate ~/ 2; i++) {
      var value =
          (32767 * 0.3 * math.sin(2 * math.pi * 440 * i / sampleRate)).round();
      byteData.setInt16(i * 2, value, Endian.little);
    }
    return RawAudioData.fromChannelsBytes(channelsBytes: [bytes]);
  }

  Future<void> _play() async {
    // One output, one sampleRate/channelCount for the whole app run.
    var output =
        _output ??= rawAudioManagerPcmSound.createOutput(
          options: RawAudioOutputOptions(sampleRate: 44100, channelCount: 1),
        );
    await output.play();
    await output.feed(_tone());
  }

  @override
  void dispose() {
    // stop() does not flush the platform queue, it just stops the flag.
    unawaited(rawAudioManagerPcmSound.stopAll());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(onPressed: _play, child: const Text('Play')),
        ElevatedButton(
          onPressed: () => rawAudioManagerPcmSound.stopAll(),
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
```

### Test the audio generation without a device

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';
import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

/// Backend neutral: pass rawAudioManagerPcmSound in the app,
/// RawAudioManagerMemory (or RawAudioManagerWav) in tests.
Future<RawAudioOutput> playSilence(RawAudioManager manager, int frames) async {
  var output = manager.createOutput(
    options: RawAudioOutputOptions(sampleRate: 8000, channelCount: 1),
  );
  await output.play();
  await output.feed(
    RawAudioData.fromChannelsBytes(channelsBytes: [Uint8List(frames * 2)]),
  );
  return output;
}

void main() {
  test('feeds the right number of frames', () async {
    var output = await playSilence(RawAudioManagerMemory(), 100);
    expect((output as RawAudioOutputMemory).channelsBytes.first.length, 200);
  });
}
```
