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

/// The flag of a compressed sample in the sample type of a sample header.
const midiSampleTypeCompressed = 0x10;

/// The flag of a ROM sample (not in the file).
const _sampleTypeRom = 0x8000;

/// The zero frames the SF2 format asks after each sample.
const _guard = 46;

/// The size of a sample header (`shdr`).
const _headerSize = 46;

/// A chunk of a RIFF file: its id and data, or, for a `LIST`, its type and
/// chunks.
class _Chunk {
  final String id;
  final Uint8List data;
  final String? listType;
  final List<_Chunk> chunks;

  _Chunk(this.id, this.data) : listType = null, chunks = const [];

  _Chunk.list(String type, this.chunks)
    : id = 'LIST',
      listType = type,
      data = Uint8List(0);

  _Chunk? find(String id) {
    for (var chunk in chunks) {
      if (chunk.id == id || chunk.listType == id) {
        return chunk;
      }
    }
    return null;
  }

  int get size => listType == null
      ? data.length
      : 4 + chunks.fold(0, (size, chunk) => size + 8 + _even(chunk.size));
}

int _even(int size) => size + (size & 1);

String _tag(Uint8List bytes, int at) =>
    ascii.decode(bytes.sublist(at, at + 4), allowInvalid: true);

/// The chunks of [bytes] from [start] to [end].
List<_Chunk> _chunks(Uint8List bytes, int start, int end) {
  var data = ByteData.sublistView(bytes);
  var chunks = <_Chunk>[];
  var at = start;
  while (at + 8 <= end) {
    var id = _tag(bytes, at);
    var size = data.getUint32(at + 4, Endian.little);
    var body = at + 8;
    if (body + size > end) {
      throw const FormatException('SoundFont: a chunk goes past its end');
    }
    if (id == 'LIST') {
      chunks.add(
        _Chunk.list(_tag(bytes, body), _chunks(bytes, body + 4, body + size)),
      );
    } else {
      chunks.add(_Chunk(id, Uint8List.sublistView(bytes, body, body + size)));
    }
    at = body + _even(size);
  }
  return chunks;
}

/// The `sfbk` chunks of [bytes]: INFO, sdta, pdta.
_Chunk _readBank(Uint8List bytes) {
  if (bytes.length < 12 ||
      _tag(bytes, 0) != 'RIFF' ||
      _tag(bytes, 8) != 'sfbk') {
    throw const FormatException('not a SoundFont (RIFF sfbk)');
  }
  var size = ByteData.sublistView(bytes).getUint32(4, Endian.little);
  var end = (8 + size).clamp(12, bytes.length);
  return _Chunk.list('sfbk', _chunks(bytes, 12, end));
}

/// The bytes of the bank [bank] (a `RIFF sfbk`).
Uint8List _writeBank(_Chunk bank) {
  var builder = BytesBuilder(copy: false);
  void write(_Chunk chunk) {
    var header = ByteData(8);
    var id = chunk.listType == null ? chunk.id : 'LIST';
    for (var i = 0; i < 4; i++) {
      header.setUint8(i, id.codeUnitAt(i));
    }
    header.setUint32(4, chunk.size, Endian.little);
    builder.add(header.buffer.asUint8List());
    var type = chunk.listType;
    if (type != null) {
      builder.add(ascii.encode(type));
      chunk.chunks.forEach(write);
    } else {
      builder.add(chunk.data);
      if (chunk.data.length.isOdd) {
        builder.addByte(0);
      }
    }
  }

  var header = ByteData(12);
  header
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, bank.size, Endian.little)
    ..setUint32(8, 0x6b626673, Endian.little); // sfbk
  builder.add(header.buffer.asUint8List());
  bank.chunks.forEach(write);
  return builder.takeBytes();
}

/// The sample headers of [bank], the last one the terminal `EOS`.
ByteData _headers(_Chunk bank) {
  var shdr = bank.find('pdta')?.find('shdr');
  if (shdr == null || shdr.data.length < _headerSize) {
    throw const FormatException('SoundFont: no sample header');
  }
  return ByteData.sublistView(shdr.data);
}

/// True when [bytes] is a SoundFont with compressed samples (an SF3); false
/// for an SF2 or anything else.
bool midiSoundFontIsCompressed(Uint8List bytes) {
  try {
    var headers = _headers(_readBank(bytes));
    for (
      var o = 0;
      o + _headerSize <= headers.lengthInBytes;
      o += _headerSize
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

/// The INFO list of [bank] with its version (`ifil`) set to [major].[minor].
_Chunk _info(_Chunk bank, int major, int minor) {
  var ifil = ByteData(4)
    ..setUint16(0, major, Endian.little)
    ..setUint16(2, minor, Endian.little);
  var info = bank.find('INFO');
  return _Chunk.list('INFO', [
    _Chunk('ifil', ifil.buffer.asUint8List()),
    for (var chunk in info?.chunks ?? const <_Chunk>[])
      if (chunk.id != 'ifil') chunk,
  ]);
}

/// The bank of [info], [smpl] and the pdta of [bank] with [shdr].
_Chunk _bank(_Chunk bank, _Chunk info, Uint8List smpl, Uint8List shdr) =>
    _Chunk.list('sfbk', [
      info,
      _Chunk.list('sdta', [_Chunk('smpl', smpl)]),
      _Chunk.list('pdta', [
        for (var chunk in bank.find('pdta')!.chunks)
          if (chunk.id == 'shdr') _Chunk('shdr', shdr) else chunk,
      ]),
    ]);

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
/// An SF2 is returned as is.
Future<Uint8List> midiSoundFontDecompress(
  Uint8List bytes, {
  void Function(int done, int total)? onProgress,
  Duration slice = const Duration(milliseconds: 16),
}) async {
  if (!midiSoundFontIsCompressed(bytes)) {
    return bytes;
  }
  var bank = _readBank(bytes);
  var smpl = bank.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var headers = _headers(bank);
  var count = headers.lengthInBytes ~/ _headerSize - 1;
  var shdr = Uint8List.fromList(
    Uint8List.sublistView(headers, 0, (count + 1) * _headerSize),
  );
  var out = ByteData.sublistView(shdr);
  var frames = BytesBuilder(copy: false);
  var position = 0;
  var guard = Uint8List(_guard * 2);
  var slicer = _Slicer(slice);
  for (var i = 0; i < count; i++) {
    var o = i * _headerSize;
    var start = headers.getUint32(o + 20, Endian.little);
    var end = headers.getUint32(o + 24, Endian.little);
    var loopStart = headers.getUint32(o + 28, Endian.little);
    var loopEnd = headers.getUint32(o + 32, Endian.little);
    var type = headers.getUint16(o + 44, Endian.little);
    Int16List pcm;
    if (type & _sampleTypeRom != 0) {
      pcm = Int16List(0);
    } else if (type & midiSampleTypeCompressed != 0) {
      if (end > smpl.length || start > end) {
        throw FormatException('SF3: sample $i past the sample data');
      }
      var decoded = decodeOgg(Uint8List.sublistView(smpl, start, end));
      var all = float32ToInt16(decoded.pcm);
      var channels = decoded.channels;
      pcm = channels == 1
          ? all
          : Int16List.fromList([
              for (var f = 0; f < decoded.frames; f++) all[f * channels],
            ]);
    } else {
      // A sample kept as is: its frames, its loop points absolute.
      if (end * 2 > smpl.length || start > end) {
        throw FormatException('SF3: sample $i past the sample data');
      }
      pcm = _frames(smpl, start, end);
      loopStart -= start;
      loopEnd -= start;
    }
    var length = pcm.length;
    var relativeStart = loopStart.clamp(0, length);
    var relativeEnd = loopEnd.clamp(relativeStart, length);
    out
      ..setUint32(o + 20, position, Endian.little)
      ..setUint32(o + 24, position + length, Endian.little)
      ..setUint32(o + 28, position + relativeStart, Endian.little)
      ..setUint32(o + 32, position + relativeEnd, Endian.little)
      ..setUint16(o + 44, type & ~midiSampleTypeCompressed, Endian.little);
    frames
      ..add(_littleEndian(pcm))
      ..add(guard);
    position += length + _guard;
    onProgress?.call(i + 1, count);
    await slicer.next();
  }
  return _writeBank(_bank(bank, _info(bank, 2, 4), frames.takeBytes(), shdr));
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
  var bank = _readBank(bytes);
  var smpl = bank.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var samples = _frames(smpl, 0, smpl.length ~/ 2);
  var headers = _headers(bank);
  var count = headers.lengthInBytes ~/ _headerSize - 1;
  var shdr = Uint8List.fromList(
    Uint8List.sublistView(headers, 0, (count + 1) * _headerSize),
  );
  var out = ByteData.sublistView(shdr);
  var streams = BytesBuilder(copy: false);
  var offset = 0;
  for (var i = 0; i < count; i++) {
    var o = i * _headerSize;
    var start = headers.getUint32(o + 20, Endian.little);
    var end = headers.getUint32(o + 24, Endian.little);
    var loopStart = headers.getUint32(o + 28, Endian.little);
    var loopEnd = headers.getUint32(o + 32, Endian.little);
    var rate = headers.getUint32(o + 36, Endian.little);
    var type = headers.getUint16(o + 44, Endian.little);
    if (type & _sampleTypeRom != 0) {
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
  return _writeBank(_bank(bank, _info(bank, 3, 0), streams.takeBytes(), shdr));
}

/// What differs between the samples of the SF2 [a] and [b]: their number,
/// and for each its name, its length, its loop points (from its start,
/// within the sample: a loop end past it is its end, as compressing keeps
/// it), its rate, its type. None when [b] is [a] compressed then
/// decompressed.
List<String> midiSoundFontSampleDifferences(Uint8List a, Uint8List b) {
  var first = _headers(_readBank(a));
  var second = _headers(_readBank(b));
  if (first.lengthInBytes != second.lengthInBytes) {
    var counts = [
      for (var headers in [first, second])
        headers.lengthInBytes ~/ _headerSize - 1,
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
  for (var o = 0; o + _headerSize < first.lengthInBytes; o += _headerSize) {
    var i = o ~/ _headerSize;
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
  var bankA = _readBank(a);
  var bankB = _readBank(b);
  var first = _headers(bankA);
  var second = _headers(bankB);
  var smplA = bankA.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var smplB = bankB.find('sdta')?.find('smpl')?.data ?? Uint8List(0);
  var dataA = ByteData.sublistView(smplA);
  var dataB = ByteData.sublistView(smplB);
  var count = first.lengthInBytes ~/ _headerSize - 1;
  return [
    for (var i = 0; i < count; i++)
      () {
        var o = i * _headerSize;
        if (o + _headerSize > second.lengthInBytes) {
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

/// The bytes of [frames], little endian whatever the host.
Uint8List _littleEndian(Int16List frames) {
  if (Endian.host == Endian.little) {
    return frames.buffer.asUint8List(
      frames.offsetInBytes,
      frames.lengthInBytes,
    );
  }
  var data = ByteData(frames.length * 2);
  for (var i = 0; i < frames.length; i++) {
    data.setInt16(i * 2, frames[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
