/// The RIFF structure of a SoundFont (`RIFF sfbk`): its chunks read as
/// views on the bytes, written back in one buffer. Internal, not exported.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The size of a sample header (`shdr`).
const soundFontHeaderSize = 46;

/// The flag of a ROM sample (not in the file) in the sample type of a
/// sample header.
const soundFontSampleTypeRom = 0x8000;

/// The zero frames the SF2 format asks after each sample.
const soundFontGuardFrames = 46;

/// A chunk of a RIFF file: its id and data, or, for a `LIST`, its type and
/// chunks.
class SoundFontChunk {
  /// The id (`LIST` for a list).
  final String id;

  /// The data (a view on the file read), empty for a list.
  final Uint8List data;

  /// The type of a list, null otherwise.
  final String? listType;

  /// The chunks of a list.
  final List<SoundFontChunk> chunks;

  /// The size of the data of a reserved chunk, written in place later; null
  /// for a chunk with its [data].
  final int? reserved;

  /// A chunk of [data].
  SoundFontChunk(this.id, this.data)
    : listType = null,
      chunks = const [],
      reserved = null;

  /// A chunk of [size] bytes, zero, to fill in the bank written.
  SoundFontChunk.reserved(this.id, int size)
    : listType = null,
      chunks = const [],
      data = Uint8List(0),
      reserved = size;

  /// A list of [chunks].
  SoundFontChunk.list(String type, this.chunks)
    : id = 'LIST',
      listType = type,
      data = Uint8List(0),
      reserved = null;

  int get _dataSize => reserved ?? data.length;

  /// The chunk [id] (or the list of that type), null when none.
  SoundFontChunk? find(String id) {
    for (var chunk in chunks) {
      if (chunk.id == id || chunk.listType == id) {
        return chunk;
      }
    }
    return null;
  }

  /// The size written in its header.
  int get size => listType == null
      ? _dataSize
      : 4 + chunks.fold(0, (size, chunk) => size + 8 + _even(chunk.size));
}

int _even(int size) => size + (size & 1);

String _tag(Uint8List bytes, int at) =>
    ascii.decode(bytes.sublist(at, at + 4), allowInvalid: true);

/// The chunks of [bytes] from [start] to [end].
List<SoundFontChunk> _chunks(Uint8List bytes, int start, int end) {
  var data = ByteData.sublistView(bytes);
  var chunks = <SoundFontChunk>[];
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
        SoundFontChunk.list(
          _tag(bytes, body),
          _chunks(bytes, body + 4, body + size),
        ),
      );
    } else {
      chunks.add(
        SoundFontChunk(id, Uint8List.sublistView(bytes, body, body + size)),
      );
    }
    at = body + _even(size);
  }
  return chunks;
}

/// The `sfbk` chunks of [bytes]: INFO, sdta, pdta (views, not copies).
SoundFontChunk soundFontReadBank(Uint8List bytes) {
  if (bytes.length < 12 ||
      _tag(bytes, 0) != 'RIFF' ||
      _tag(bytes, 8) != 'sfbk') {
    throw const FormatException('not a SoundFont (RIFF sfbk)');
  }
  var size = ByteData.sublistView(bytes).getUint32(4, Endian.little);
  var end = (8 + size).clamp(12, bytes.length);
  return SoundFontChunk.list('sfbk', _chunks(bytes, 12, end));
}

/// The bytes of the bank [bank] (a `RIFF sfbk`), in one buffer; the data
/// of a reserved chunk left zero, its offset given to [onReserved].
Uint8List soundFontWriteBank(
  SoundFontChunk bank, {
  void Function(int offset)? onReserved,
}) {
  var bytes = Uint8List(8 + bank.size);
  var data = ByteData.sublistView(bytes);
  var at = 0;
  void tag(String id) {
    for (var i = 0; i < 4; i++) {
      bytes[at + i] = id.codeUnitAt(i);
    }
    at += 4;
  }

  void size(int size) {
    data.setUint32(at, size, Endian.little);
    at += 4;
  }

  void write(SoundFontChunk chunk) {
    var type = chunk.listType;
    tag(type == null ? chunk.id : 'LIST');
    size(chunk.size);
    if (type != null) {
      tag(type);
      chunk.chunks.forEach(write);
      return;
    }
    if (chunk.reserved == null) {
      bytes.setRange(at, at + chunk.data.length, chunk.data);
    } else {
      onReserved?.call(at);
    }
    at += _even(chunk._dataSize);
  }

  tag('RIFF');
  size(bank.size);
  tag('sfbk');
  bank.chunks.forEach(write);
  return bytes;
}

/// The sample headers of [bank], the last one the terminal `EOS`.
ByteData soundFontSampleHeaders(SoundFontChunk bank) {
  var shdr = bank.find('pdta')?.find('shdr');
  if (shdr == null || shdr.data.length < soundFontHeaderSize) {
    throw const FormatException('SoundFont: no sample header');
  }
  return ByteData.sublistView(shdr.data);
}

/// The sample frames of [bank] (`sdta` `smpl`), empty when none.
Uint8List soundFontSampleData(SoundFontChunk bank) =>
    bank.find('sdta')?.find('smpl')?.data ?? Uint8List(0);

/// The INFO list of [bank] with its version (`ifil`) set to [major].[minor].
SoundFontChunk soundFontInfoVersion(SoundFontChunk bank, int major, int minor) {
  var ifil = ByteData(4)
    ..setUint16(0, major, Endian.little)
    ..setUint16(2, minor, Endian.little);
  var info = bank.find('INFO');
  return SoundFontChunk.list('INFO', [
    SoundFontChunk('ifil', ifil.buffer.asUint8List()),
    for (var chunk in info?.chunks ?? const <SoundFontChunk>[])
      if (chunk.id != 'ifil') chunk,
  ]);
}

/// The bank of [info], [smpl] and the pdta of [bank] with [shdr].
SoundFontChunk soundFontBankWith(
  SoundFontChunk bank,
  SoundFontChunk info,
  SoundFontChunk smpl,
  Uint8List shdr,
) => SoundFontChunk.list('sfbk', [
  info,
  SoundFontChunk.list('sdta', [smpl]),
  SoundFontChunk.list('pdta', [
    for (var chunk in bank.find('pdta')!.chunks)
      if (chunk.id == 'shdr') SoundFontChunk('shdr', shdr) else chunk,
  ]),
]);
