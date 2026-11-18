/// SF3: an SF2 whose samples are compressed, each one an Ogg Vorbis stream
/// (the format of MuseScore, read by FluidSynth and SpessaSynth): a bank of
/// 32 MB in SF2 takes 5 to 8 MB.
///
/// The synth reads SF2 only: [midiSoundFontDecompress] turns an SF3 into the
/// SF2 it stands for (once, when it is downloaded or imported), with a pure
/// Dart Vorbis decoder (`milomedy_vorbis`, on io and the web).
/// [midiSoundFontCompress] does the opposite with an encoder given by the
/// caller (a tool running ffmpeg).
///
/// In an SF3, the `start` and `end` of a compressed sample (its type with
/// [midiSampleTypeCompressed]) are byte offsets of its Ogg stream in the
/// `smpl` chunk, and its loop points are relative to its first frame.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';

import 'riff.dart';

/// The flag of a compressed sample in the sample type of a sample header.
const midiSampleTypeCompressed = 0x10;

/// True when [bytes] is a SoundFont with compressed samples (an SF3); false
/// for an SF2 or anything else.
bool midiSoundFontIsCompressed(Uint8List bytes) {
  try {
    var headers = soundFontSampleHeaders(soundFontReadBank(bytes));
    for (
      var o = 0;
      o + soundFontHeaderSize <= headers.lengthInBytes;
      o += soundFontHeaderSize
    ) {
      if (headers.getUint16(o + 44, Endian.little) & midiSampleTypeCompressed !=
          0) {
        return true;
      }
    }
  } on FormatException {
    // Not a SoundFont: not an SF3.
  }
  return false;
}

/// Lets the event loop run every [slice] (a page stays responsive).
class _Slicer {
  final Duration slice;
  final _watch = Stopwatch()..start();

  _Slicer(this.slice);

  Future<void> next() async {
    if (_watch.elapsed >= slice) {
      await Future<void>.delayed(Duration.zero);
      _watch.reset();
    }
  }
}

/// The SF2 of the SF3 [bytes]: each compressed sample decoded to 16-bit
/// frames, followed by the 46 zero frames of the format, its loop points
/// made absolute (and kept within the sample); the other samples copied;
/// the version set to 2.4. [onProgress] tells the samples done out of all.
///
/// It takes a few seconds for a General MIDI bank (920 samples, 32 MB
/// once decoded: about 4 s on the VM): the event loop runs every [slice].
/// The SF2 is written in one buffer: the length of each sample read first
/// (the last granule position of its stream), its frames then decoded in
/// place; the setups shared by the streams parsed once
/// ([VorbisSetupCache]). An SF2 is returned as is.
Future<Uint8List> midiSoundFontDecompress(
  Uint8List bytes, {
  void Function(int done, int total)? onProgress,
  Duration slice = const Duration(milliseconds: 16),
}) async {
  if (!midiSoundFontIsCompressed(bytes)) {
    return bytes;
  }
  var bank = soundFontReadBank(bytes);
  var smpl = bank.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var headers = soundFontSampleHeaders(bank);
  var count = headers.lengthInBytes ~/ soundFontHeaderSize - 1;
  var shdr = Uint8List.fromList(
    Uint8List.sublistView(headers, 0, (count + 1) * soundFontHeaderSize),
  );
  var out = ByteData.sublistView(shdr);
  var slicer = _Slicer(slice);

  // The place of each sample in the SF2: its length, its loop points.
  var position = 0;
  for (var i = 0; i < count; i++) {
    var o = i * soundFontHeaderSize;
    var start = headers.getUint32(o + 20, Endian.little);
    var end = headers.getUint32(o + 24, Endian.little);
    var loopStart = headers.getUint32(o + 28, Endian.little);
    var loopEnd = headers.getUint32(o + 32, Endian.little);
    var type = headers.getUint16(o + 44, Endian.little);
    int length;
    if (type & soundFontSampleTypeRom != 0) {
      length = 0;
    } else if (type & midiSampleTypeCompressed != 0) {
      if (end > smpl.length || start > end) {
        throw FormatException('SF3: sample $i past the sample data');
      }
      length = probeOgg(Uint8List.sublistView(smpl, start, end)).frames;
    } else {
      // A sample kept as is: its loop points absolute.
      if (end * 2 > smpl.length || start > end) {
        throw FormatException('SF3: sample $i past the sample data');
      }
      length = end - start;
      loopStart -= start;
      loopEnd -= start;
    }
    var relativeStart = loopStart.clamp(0, length);
    var relativeEnd = loopEnd.clamp(relativeStart, length);
    out
      ..setUint32(o + 20, position, Endian.little)
      ..setUint32(o + 24, position + length, Endian.little)
      ..setUint32(o + 28, position + relativeStart, Endian.little)
      ..setUint32(o + 32, position + relativeEnd, Endian.little)
      ..setUint16(o + 44, type & ~midiSampleTypeCompressed, Endian.little);
    position += length + soundFontGuardFrames;
    await slicer.next();
  }

  // The SF2, its frames zero; then each sample decoded in place.
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
  var frames = Int16List.view(sf2.buffer, framesOffset, position);
  var source = ByteData.sublistView(smpl);
  var setups = VorbisSetupCache();
  for (var i = 0; i < count; i++) {
    var o = i * soundFontHeaderSize;
    var start = headers.getUint32(o + 20, Endian.little);
    var end = headers.getUint32(o + 24, Endian.little);
    var type = headers.getUint16(o + 44, Endian.little);
    var at = out.getUint32(o + 20, Endian.little);
    var length = out.getUint32(o + 24, Endian.little) - at;
    if (type & soundFontSampleTypeRom != 0) {
      // Not in the file.
    } else if (type & midiSampleTypeCompressed != 0) {
      var decoded = decodeOggInt16(
        Uint8List.sublistView(smpl, start, end),
        frames,
        offset: at,
        firstChannelOnly: true,
        setups: setups,
      );
      if (decoded != length) {
        throw FormatException('SF3: sample $i decoded $decoded of $length');
      }
    } else {
      for (var f = 0; f < length; f++) {
        frames[at + f] = source.getInt16((start + f) * 2, Endian.little);
      }
    }
    if (Endian.host != Endian.little) {
      var view = ByteData.sublistView(frames, at, at + length);
      for (var f = 0; f < length; f++) {
        view.setInt16(f * 2, view.getInt16(f * 2), Endian.little);
      }
    }
    onProgress?.call(i + 1, count);
    await slicer.next();
  }
  return sf2;
}

/// Compresses one sample: its 16-bit [frames] (mono) at [sampleRate] to an
/// Ogg Vorbis stream.
typedef MidiSoundFontSampleEncoder =
    Future<Uint8List> Function(Int16List frames, int sampleRate);

/// The SF3 of the SF2 [bytes]: each sample compressed by [encode] (its
/// frames, without the 46 zero ones), its loop points made relative; the
/// version set to 3.0. [onProgress] tells the samples done out of all.
///
/// The encoder must keep the length (the Ogg granule positions): the loop
/// points of a sample are frames of its stream.
Future<Uint8List> midiSoundFontCompress(
  Uint8List bytes, {
  required MidiSoundFontSampleEncoder encode,
  void Function(int done, int total)? onProgress,
}) async {
  if (midiSoundFontIsCompressed(bytes)) {
    throw const FormatException('already compressed (SF3)');
  }
  var bank = soundFontReadBank(bytes);
  var smpl = bank.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var samples = _frames(smpl, 0, smpl.length ~/ 2);
  var headers = soundFontSampleHeaders(bank);
  var count = headers.lengthInBytes ~/ soundFontHeaderSize - 1;
  var shdr = Uint8List.fromList(
    Uint8List.sublistView(headers, 0, (count + 1) * soundFontHeaderSize),
  );
  var out = ByteData.sublistView(shdr);
  var streams = BytesBuilder(copy: false);
  var offset = 0;
  for (var i = 0; i < count; i++) {
    var o = i * soundFontHeaderSize;
    var start = headers.getUint32(o + 20, Endian.little);
    var end = headers.getUint32(o + 24, Endian.little);
    var loopStart = headers.getUint32(o + 28, Endian.little);
    var loopEnd = headers.getUint32(o + 32, Endian.little);
    var rate = headers.getUint32(o + 36, Endian.little);
    var type = headers.getUint16(o + 44, Endian.little);
    if (type & soundFontSampleTypeRom != 0) {
      throw FormatException('sample $i is in ROM, not in the file');
    }
    if (end > samples.length || start > end) {
      throw FormatException('sample $i past the sample data');
    }
    var ogg = await encode(Int16List.sublistView(samples, start, end), rate);
    out
      ..setUint32(o + 20, offset, Endian.little)
      ..setUint32(o + 24, offset + ogg.length, Endian.little)
      ..setUint32(
        o + 28,
        (loopStart - start).clamp(0, end - start),
        Endian.little,
      )
      ..setUint32(
        o + 32,
        (loopEnd - start).clamp(0, end - start),
        Endian.little,
      )
      ..setUint16(o + 44, type | midiSampleTypeCompressed, Endian.little);
    streams.add(ogg);
    offset += ogg.length;
    onProgress?.call(i + 1, count);
  }
  return soundFontWriteBank(
    soundFontBankWith(
      bank,
      soundFontInfoVersion(bank, 3, 0),
      SoundFontChunk('smpl', streams.takeBytes()),
      shdr,
    ),
  );
}

/// What differs between the samples of the SF2 [a] and [b]: their number,
/// and for each its name, its length, its loop points (from its start,
/// within the sample: a loop end past it is its end, as compressing keeps
/// it), its rate, its type. None when [b] is [a] compressed then
/// decompressed.
List<String> midiSoundFontSampleDifferences(Uint8List a, Uint8List b) {
  var first = soundFontSampleHeaders(soundFontReadBank(a));
  var second = soundFontSampleHeaders(soundFontReadBank(b));
  if (first.lengthInBytes != second.lengthInBytes) {
    var counts = [
      for (var headers in [first, second])
        headers.lengthInBytes ~/ soundFontHeaderSize - 1,
    ];
    return ['samples: ${counts.first} vs ${counts.last}'];
  }
  String name(ByteData headers, int o) => ascii.decode(
    Uint8List.sublistView(headers, o, o + 20).takeWhile((c) => c != 0).toList(),
    allowInvalid: true,
  );
  List<int> shape(ByteData headers, int o) {
    int at(int offset) => headers.getUint32(o + offset, Endian.little);
    var start = at(20);
    var length = at(24) - start;
    var loopStart = (at(28) - start).clamp(0, length);
    return [
      length,
      loopStart,
      (at(32) - start).clamp(loopStart, length),
      at(36),
      headers.getUint16(o + 44, Endian.little) & ~midiSampleTypeCompressed,
    ];
  }

  var differences = <String>[];
  for (
    var o = 0;
    o + soundFontHeaderSize < first.lengthInBytes;
    o += soundFontHeaderSize
  ) {
    var i = o ~/ soundFontHeaderSize;
    var (nameA, nameB) = (name(first, o), name(second, o));
    var (shapeA, shapeB) = (shape(first, o), shape(second, o));
    if (nameA != nameB || '$shapeA' != '$shapeB') {
      differences.add(
        'sample $i: $nameA $shapeA vs $nameB $shapeB '
        '(length, loop start, loop end, rate, type)',
      );
    }
  }
  return differences;
}

/// The signal to noise ratio (dB) of each sample of the SF2 [b] against the
/// same sample of the SF2 [a] (its frames, the noise what differs): how much
/// a compression lost. Infinite for a sample unchanged; 0 for a silent one
/// or when the samples differ in number or length.
List<double> midiSoundFontSampleSnr(Uint8List a, Uint8List b) {
  var bankA = soundFontReadBank(a);
  var bankB = soundFontReadBank(b);
  var first = soundFontSampleHeaders(bankA);
  var second = soundFontSampleHeaders(bankB);
  var smplA = bankA.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var smplB = bankB.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var dataA = ByteData.sublistView(smplA);
  var dataB = ByteData.sublistView(smplB);
  var count = first.lengthInBytes ~/ soundFontHeaderSize - 1;
  return [
    for (var i = 0; i < count; i++)
      () {
        var o = i * soundFontHeaderSize;
        if (o + soundFontHeaderSize > second.lengthInBytes) {
          return 0.0;
        }
        var startA = first.getUint32(o + 20, Endian.little);
        var startB = second.getUint32(o + 20, Endian.little);
        var length = first.getUint32(o + 24, Endian.little) - startA;
        if (second.getUint32(o + 24, Endian.little) - startB != length) {
          return 0.0;
        }
        var signal = 0.0;
        var noise = 0.0;
        for (var f = 0; f < length; f++) {
          var x = dataA.getInt16((startA + f) * 2, Endian.little);
          var y = dataB.getInt16((startB + f) * 2, Endian.little);
          signal += x * x;
          noise += (x - y) * (x - y);
        }
        if (signal == 0) {
          return 0.0;
        }
        return noise == 0
            ? double.infinity
            : 10 * math.log(signal / noise) / math.ln10;
      }(),
  ];
}

/// The 16-bit frames [start] to [end] of [smpl] (little endian, whatever
/// the alignment of its bytes).
Int16List _frames(Uint8List smpl, int start, int end) {
  var data = ByteData.sublistView(smpl);
  var frames = Int16List(end - start);
  for (var i = 0; i < frames.length; i++) {
    frames[i] = data.getInt16((start + i) * 2, Endian.little);
  }
  return frames;
}
