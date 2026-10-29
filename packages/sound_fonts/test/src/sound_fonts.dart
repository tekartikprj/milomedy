import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

/// Another valid SoundFont: the tiny one named "Tiny copy SoundFont".
Uint8List copySoundFontBytes() {
  var bytes = midiTinySoundFontBytes();
  var from = ascii.encode('Tiny test');
  var to = ascii.encode('Tiny copy');
  for (var i = 0; i + from.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < from.length && match; j++) {
      match = bytes[i + j] == from[j];
    }
    if (match) {
      bytes.setRange(i, i + to.length, to);
      return bytes;
    }
  }
  throw StateError('name not found');
}

/// The git blob id of [bytes].
String gitBlobSha1(Uint8List bytes) => sha1.convert([
  ...utf8.encode('blob ${bytes.length}\u0000'),
  ...bytes,
]).toString();
