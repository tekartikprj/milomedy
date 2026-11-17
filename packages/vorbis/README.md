# milomedy_vorbis

Ogg Vorbis decoding in pure Dart, for io and the web (VM, dart2js,
dart2wasm): the samples of an SF3 SoundFont, each an Ogg Vorbis stream
(`milomedy_sound_fonts` turns an SF3 into the SF2 the synth reads).

```dart
import 'package:milomedy_vorbis/vorbis.dart';

var decoded = decodeOgg(oggBytes); // channels, sampleRate, frames, pcm
var frames = float32ToInt16(decoded.pcm);
```

## Origin and licence

The decoder of [vorbis_decoder](https://github.com/dotkebi/vorbis_decoder)
0.0.1-dev.1 by Myoungjin Ko, itself a port of
[NVorbis](https://github.com/NVorbis/NVorbis) by Andrew Ward, both under the
MIT licence ([LICENSE](LICENSE), kept as is). Its `lib/` is copied here with
one change: `BitReader.read` of more than 32 bits adds powers of two instead
of shifting, because the JavaScript bitwise operators of dart2js keep 32 bits
(the 48-bit `vorbis` signature of the setup header failed to read there:
"invalid Vorbis setup header"). The other differences are the formatting and
this library's name.

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
