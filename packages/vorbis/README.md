# milomedy_vorbis

Ogg Vorbis decoding in pure Dart, for io and the web (VM, dart2js,
dart2wasm): the samples of an SF3 SoundFont, each an Ogg Vorbis stream
(`milomedy_sound_fonts` turns an SF3 into the SF2 the synth reads).

```dart
import 'package:milomedy_vorbis/vorbis.dart';

var decoded = decodeOgg(oggBytes); // channels, sampleRate, frames, pcm
var frames = float32ToInt16(decoded.pcm);

// The same 16-bit frames, written in place (no float frames, no copy).
var output = Int16List(probeOgg(oggBytes).frames);
decodeOggInt16(oggBytes, output, firstChannelOnly: true);

// Many streams of the same encoder (the samples of an SF3): their setup
// parsed once (the last 16 used kept, about 0.3 MB each).
var setups = VorbisSetupCache();
decodeOggInt16(sample, output, offset: at, setups: setups);
```

## Origin and licence

The decoder of [vorbis_decoder](https://github.com/dotkebi/vorbis_decoder)
0.0.1-dev.1 by Myoungjin Ko, itself a port of
[NVorbis](https://github.com/NVorbis/NVorbis) by Andrew Ward, both under the
MIT licence ([LICENSE](LICENSE), kept as is). Its `lib/` is copied here with
these changes:

- `BitReader.read` of more than 32 bits adds powers of two instead of
  shifting, because the JavaScript bitwise operators of dart2js keep 32 bits
  (the 48-bit `vorbis` signature of the setup header failed to read there:
  "invalid Vorbis setup header").
- `decodeOggInt16` and `VorbisSetupCache`: the frames of a block go to a
  sink (float or 16-bit), the setup can be shared. An SF3 decoded this way
  (GeneralUser GS, 920 streams, 90 setups) makes a third of the garbage it
  made (181 MB instead of 578 on the VM), the same bytes.
- The formatting and this library's name.

What it does not support (from vorbis_decoder): Floor 0, chained Ogg streams.

## Tests

`test/data/sine.ogg` is half a second of a 440 Hz sine made by
`dart run tool/make_fixture.dart` (ffmpeg's libvorbis). The tests decode it
on the VM and in Chrome:

```sh
dart test -p vm
dart test -p chrome
dart test -p chrome -c dart2wasm
```
