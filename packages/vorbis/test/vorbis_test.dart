@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';
import 'package:test/test.dart';

import 'src/check.dart';

void main() {
  var ogg = Uint8List.fromList(File('test/data/sine.ogg').readAsBytesSync());

  test('the sine decoded', () => checkSine(ogg));

  test('16-bit frames, setups kept', () => checkInt16(ogg));

  test('not Ogg Vorbis: refused', () {
    expect(
      () => decodeOgg(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<VorbisDecoderException>()),
    );
    var corrupt = Uint8List.fromList(ogg)..[ogg.length ~/ 2] ^= 0xff;
    expect(() => decodeOgg(corrupt), throwsA(isA<VorbisDecoderException>()));
  });
}
