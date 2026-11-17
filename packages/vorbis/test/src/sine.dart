import 'dart:math' as math;
import 'dart:typed_data';

/// The rate of the fixture.
const sineSampleRate = 22050;

/// Its length: half a second.
const sineFrames = 11025;

/// Its frames: a 440 Hz sine at half scale, 16 bits.
Int16List sineSamples() => Int16List.fromList([
  for (var i = 0; i < sineFrames; i++)
    (16000 * math.sin(2 * math.pi * 440 * i / sineSampleRate)).round(),
]);
