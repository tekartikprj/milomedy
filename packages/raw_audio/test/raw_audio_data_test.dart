import 'dart:math';
import 'dart:typed_data';

import 'package:tekartik_raw_audio/generator.dart';
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:test/test.dart';

void main() {
  test('fromInt16List is little-endian pcm16', () {
    var data = RawAudioData.fromInt16List([1, -2, 0x1234]);
    expect(data.channelsBytes.single, [1, 0, 0xFE, 0xFF, 0x34, 0x12]);
    expect(data.frameCount, 3);
    // The generators too: 440 Hz at 44100 Hz is 100 samples a period.
    var sine = pcm16GenerateSineWaveAudioData().channelsBytes.single;
    var samples = sine.buffer.asByteData();
    for (var i = 0; i < 100; i += 5) {
      expect(
        samples.getInt16(i * 2, Endian.little),
        (sin(2 * pi * i / 100) * 0.5 * 32767).toInt(),
      );
    }
  });

  test('subFrames clamps the start', () {
    var data = RawAudioData.fromInt16List([1, 2, 3]);
    expect(data.subFrames(-1, 2).channelsBytes.single, [1, 0, 2, 0]);
    expect(data.subFrames(1, 10).channelsBytes.single, [2, 0, 3, 0]);
  });
}
