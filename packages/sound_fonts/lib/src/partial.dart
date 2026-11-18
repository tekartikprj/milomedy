/// The SoundFont of a song: an SF2 with the whole definition of a
/// SoundFont (SF2 or SF3) and only some of its samples. Internal, not
/// exported (`MidiSoundFontSampler` uses it).
library;

import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';

import 'riff.dart';

/// The flag of a compressed sample in the sample type of a sample header.
const _compressed = 0x10;

/// The frames of the silence the samples left out point to.
const _silenceFrames = 32;

/// The 16-bit frames of sample [index] of [bank] (read by
/// `soundFontReadBank`, an SF2 or an SF3): its Ogg stream decoded for a
/// compressed one (its first channel, as the SF2 it stands for), copied for
/// another; none for a ROM sample. A [FormatException] for a sample out of
/// the sample data, a stream that does not decode or decodes to another
/// length than its last granule.
Int16List soundFontSampleFrames(
  SoundFontChunk bank,
  int index, {
  VorbisSetupCache? setups,
}) {
  var headers = soundFontSampleHeaders(bank);
  var count = headers.lengthInBytes ~/ soundFontHeaderSize - 1;
  if (index < 0 || index >= count) {
    throw RangeError.range(index, 0, count - 1, 'index');
  }
  var o = index * soundFontHeaderSize;
  var start = headers.getUint32(o + 20, Endian.little);
  var end = headers.getUint32(o + 24, Endian.little);
  var type = headers.getUint16(o + 44, Endian.little);
  var smpl = soundFontSampleData(bank);
  if (type & soundFontSampleTypeRom != 0) {
    return Int16List(0);
  }
  if (type & _compressed != 0) {
    if (end > smpl.length || start > end) {
      throw FormatException('SF3: sample $index past the sample data');
    }
    var stream = Uint8List.sublistView(smpl, start, end);
    var frames = Int16List(probeOgg(stream).frames);
    var decoded = decodeOggInt16(
      stream,
      frames,
      firstChannelOnly: true,
      setups: setups,
    );
    if (decoded != frames.length) {
      throw FormatException(
        'SF3: sample $index decoded $decoded of ${frames.length}',
      );
    }
    return frames;
  }
  if (end * 2 > smpl.length || start > end) {
    throw FormatException('SoundFont: sample $index past the sample data');
  }
  var data = ByteData.sublistView(smpl);
  var frames = Int16List(end - start);
  for (var f = 0; f < frames.length; f++) {
    frames[f] = data.getInt16((start + f) * 2, Endian.little);
  }
  return frames;
}

/// The SF2 of [bank] (an SF2 or an SF3) with the samples of [frames] only
/// (by index, the frames of [soundFontSampleFrames]), packed, each followed
/// by the 46 zero frames of the format, its loop points made absolute and
/// kept within it; the version 2.4 (as a decompressed SF3).
///
/// Every other sample points to a silence of 32 frames, with [bound]
/// frames of zeros before and after (the largest address offset of a zone,
/// `MidiSoundFontDefinition.addressOffsetBound`), as are the samples given
/// at both ends of the sample data: a zone reading before or after its
/// sample stays within the data (the synth refuses a SoundFont otherwise)
/// and reads zeros there.
Uint8List soundFontWithSamples(
  SoundFontChunk bank,
  Map<int, Int16List> frames, {
  required int bound,
}) {
  var headers = soundFontSampleHeaders(bank);
  var count = headers.lengthInBytes ~/ soundFontHeaderSize - 1;
  var shdr = Uint8List.fromList(
    Uint8List.sublistView(headers, 0, (count + 1) * soundFontHeaderSize),
  );
  var out = ByteData.sublistView(shdr);
  var silence = bound;
  var position = 2 * bound + _silenceFrames + soundFontGuardFrames;
  var places = <int, int>{};
  for (var i = 0; i < count; i++) {
    var o = i * soundFontHeaderSize;
    var type = headers.getUint16(o + 44, Endian.little);
    var sample = frames[i];
    if (sample == null) {
      out
        ..setUint32(o + 20, silence, Endian.little)
        ..setUint32(o + 24, silence + _silenceFrames, Endian.little)
        ..setUint32(o + 28, silence, Endian.little)
        ..setUint32(o + 32, silence + _silenceFrames, Endian.little)
        ..setUint16(o + 44, type & ~_compressed, Endian.little);
      continue;
    }
    var start = headers.getUint32(o + 20, Endian.little);
    var loopStart = headers.getUint32(o + 28, Endian.little);
    var loopEnd = headers.getUint32(o + 32, Endian.little);
    if (type & _compressed == 0) {
      // Absolute in an SF2, from the first frame in an SF3.
      loopStart -= start;
      loopEnd -= start;
    }
    var length = sample.length;
    var relativeStart = loopStart.clamp(0, length);
    var relativeEnd = loopEnd.clamp(relativeStart, length);
    out
      ..setUint32(o + 20, position, Endian.little)
      ..setUint32(o + 24, position + length, Endian.little)
      ..setUint32(o + 28, position + relativeStart, Endian.little)
      ..setUint32(o + 32, position + relativeEnd, Endian.little)
      ..setUint16(o + 44, type & ~_compressed, Endian.little);
    places[i] = position;
    position += length + soundFontGuardFrames;
  }
  // Room after the last sample.
  position += bound;

  var framesOffset = 0;
  var sf2 = soundFontWriteBank(
    soundFontBankWith(
      bank,
      soundFontInfoVersion(bank, 2, 4),
      SoundFontChunk.reserved('smpl', position * 2),
      shdr,
    ),
    onReserved: (offset) => framesOffset = offset,
  );
  // RIFF chunks are even: the frames are aligned.
  var pool = Int16List.view(sf2.buffer, framesOffset, position);
  for (var MapEntry(key: i, value: sample) in frames.entries) {
    var at = places[i];
    if (at == null) {
      continue;
    }
    pool.setRange(at, at + sample.length, sample);
    if (Endian.host != Endian.little) {
      var view = ByteData.sublistView(pool, at, at + sample.length);
      for (var f = 0; f < sample.length; f++) {
        view.setInt16(f * 2, view.getInt16(f * 2), Endian.little);
      }
    }
  }
  return sf2;
}
