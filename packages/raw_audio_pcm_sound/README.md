# tekartik_raw_audio_pcm_sound

The [tekartik_raw_audio](../raw_audio) output API on the device speaker,
through [flutter_pcm_sound](https://pub.dev/packages/flutter_pcm_sound): the
16 bit PCM frames you `feed` are played, and a callback asks for more when the
queue runs low. Flutter on Android, iOS and macOS only (the platforms of
flutter_pcm_sound): no web, Linux or Windows.

## Getting started

Not on pub.dev, a git dependency:

```yaml
dependencies:
  tekartik_raw_audio_pcm_sound:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/raw_audio_pcm_sound
```

```dart
import 'dart:math';

import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

/// One second of a 440 Hz beep.
Future<void> beep() async {
  const sampleRate = 44100;
  var output = rawAudioManagerPcmSound.createOutput(
    options: RawAudioOutputOptions(sampleRate: sampleRate, channelCount: 1),
  );
  await output.play();
  await output.feed(
    RawAudioData.fromInt16List([
      for (var i = 0; i < sampleRate; i++)
        (8000 * sin(2 * pi * 440 * i / sampleRate)).round(),
    ]),
  );
}
```

Write the sound making code against `RawAudioManager`: test it with
`RawAudioManagerMemory` (tekartik_raw_audio) or `RawAudioManagerWav`
(tekartik_raw_audio_wav, a file), and give it `rawAudioManagerPcmSound` in
the app.

## Good to know

* One sample rate and channel count for the whole app run: the first output
  sets up the platform, another output with other options throws
  `UnsupportedError`. Create one output and keep it.
* Mono is the simple case. With `channelCount: 2` only the first channel
  bytes are sent, and the platform reads them as interleaved left/right
  samples: build that interleaved buffer yourself.
* Feed long sounds chunk by chunk from
  `RawAudioOutputFeedOptions(feedThreshold: frames, onFeed: ...)`; the first
  chunk is yours to feed.
* `stop()` and `stopAll()` do not flush what is queued: stop feeding.

More, with a streaming and a widget example: the package skill
[skills/tekartik-raw-audio-pcm-sound-setup/SKILL.md](skills/tekartik-raw-audio-pcm-sound-setup/SKILL.md).
