import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';
import 'package:test/test.dart';

import 'sine.dart';

/// Checks the decoding of `test/data/sine.ogg` ([ogg]): its stream, its
/// exact length, its frames close to the sine encoded.
void checkSine(Uint8List ogg) {
  var info = probeOgg(ogg);
  expect(
    (info.channels, info.sampleRate, info.frames),
    (1, sineSampleRate, sineFrames),
  );
  var decoded = decodeOgg(ogg);
  expect(decoded.frames, sineFrames);
  var pcm = float32ToInt16(decoded.pcm);
  expect(pcm, hasLength(sineFrames));
  var original = sineSamples();
  var signal = 0.0;
  var noise = 0.0;
  for (var i = 0; i < sineFrames; i++) {
    signal += original[i] * original[i];
    noise += (original[i] - pcm[i]) * (original[i] - pcm[i]);
  }
  // A pure tone at quality 4: far above 30 dB.
  expect(signal / noise, greaterThan(1000));
}

/// Checks the 16-bit decoding of [ogg] (`test/data/sine.ogg`): the frames of
/// [float32ToInt16] of [decodeOgg], where asked; the setup parsed once for
/// two streams with the same headers.
void checkInt16(Uint8List ogg) {
  var expected = float32ToInt16(decodeOgg(ogg).pcm);
  var frames = expected.length;
  // From an offset, the values around left as they were.
  var output = Int16List(frames + 10)..fillRange(0, frames + 10, 7);
  expect(decodeOggInt16(ogg, output, offset: 4), frames);
  expect(output.sublist(0, 4), [7, 7, 7, 7]);
  expect(output.sublist(4, 4 + frames), expected);
  expect(output.sublist(4 + frames), [7, 7, 7, 7, 7, 7]);
  // A mono stream: its first channel is all of it.
  var mono = Int16List(frames);
  decodeOggInt16(ogg, mono, firstChannelOnly: true);
  expect(mono, expected);
  // Too small: refused before decoding.
  expect(() => decodeOggInt16(ogg, Int16List(frames - 1)), throwsArgumentError);

  var setups = VorbisSetupCache(maximum: 1);
  var first = Int16List(frames);
  var second = Int16List(frames);
  decodeOggInt16(ogg, first, setups: setups);
  decodeOggInt16(ogg, second, setups: setups);
  expect((setups.misses, setups.hits), (1, 1));
  expect(first, expected);
  expect(second, expected);
  expect(float32ToInt16(decodeOgg(ogg, setups: setups).pcm), expected);
  expect(setups.hits, 2);
}
