# tekartik_raw_audio_wav

The [tekartik_raw_audio](../raw_audio) output API written to a WAV file
instead of a speaker: what you `feed` is kept in memory and given back as a
[`Wav`](https://pub.dev/packages/wav) (16 bit PCM) to write. Pure Dart: VM,
web, Flutter. Handy to test sound generating code, or to render it to a file.

## Getting started

Not on pub.dev, a git dependency:

```yaml
dependencies:
  tekartik_raw_audio_wav:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/raw_audio_wav
```

```dart
import 'package:tekartik_raw_audio_wav/raw_audio_wav.dart';

Future<void> main() async {
  var output = RawAudioManagerWav().createOutput(
    options: RawAudioOutputOptions(sampleRate: 8000, channelCount: 1),
  );
  // Samples from -32768 to 32767: a square wave, 1 s at 200 Hz.
  await output.feed(
    RawAudioData.fromInt16List([
      for (var i = 0; i < 8000; i++) (i ~/ 20).isEven ? 8000 : -8000,
    ]),
  );
  var wav = output.wav; // build it once, at the end
  print('${wav.duration} s');
  // wav.write() gives the bytes; on io: await wav.writeFile('square.wav');
}
```

A runnable example writing a scale: `dart run example/generate_sin_wavfile.dart`
(to `.local/example.wav`).

## Good to know

* Data is 16 bit PCM, little-endian, one `Uint8List` per channel
  (`RawAudioData.fromChannelsBytes(channelsBytes: [left, right])`), or
  `RawAudioData.fromInt16List(samples)` for one channel. The generators of
  `tekartik_raw_audio` give that too.
* Give `channelCount: 1` for mono data: the default output has 2 channels.
* `play()` and `stop()` do nothing here, and `onFeed` is never called: `feed`
  only appends, everything stays in memory.
* Only writes: read a file with `Wav.read(bytes)` (package `wav`) or with
  `tekartik_wav`.
* The other backend: `tekartik_raw_audio_pcm_sound`, the speaker (Flutter).
