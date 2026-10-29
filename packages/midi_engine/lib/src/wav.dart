/// WAV files: 16-bit PCM, from interleaved float samples (from accordelio).
library;

import 'dart:typed_data';

/// The bytes of a 16-bit PCM WAV file of the interleaved [samples] (-1 to
/// 1, clipped), [channels] channels at [sampleRate].
Uint8List midiWavBytes(
  Float32List samples, {
  required int sampleRate,
  int channels = 2,
}) {
  var dataLength = samples.length * 2;
  var bytes = ByteData(44 + dataLength);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    var value = (samples[i] * 32767).round();
    if (value > 32767) {
      value = 32767;
    } else if (value < -32768) {
      value = -32768;
    }
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
