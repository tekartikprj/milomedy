@TestOn('vm')
library;

import 'dart:io';

import 'package:milomedy_midi_asset/midi_asset.dart';
import 'package:test/test.dart';

void main() {
  // The files are those the code makes: dart run tool/generate.dart after a
  // change.
  test('lib/midi holds the songs as the code makes them', () {
    var files = Directory('lib/midi').listSync().whereType<File>().toList();
    expect(files, hasLength(midiAssetSongs.length));
    for (var song in midiAssetSongs) {
      expect(
        File('lib/${song.path}').readAsBytesSync(),
        song.toBytes(),
        reason: '${song.id}: dart run tool/generate.dart',
      );
    }
  });
}
