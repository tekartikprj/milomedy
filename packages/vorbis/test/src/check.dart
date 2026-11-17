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
