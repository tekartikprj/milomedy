// ignore_for_file: avoid_print

import 'dart:io';

import 'package:milomedy_midi_asset/midi_asset.dart';

/// Writes the MIDI file of each song of the catalog in `lib/midi/`.
Future<void> main() async {
  await Directory('lib/midi').create(recursive: true);
  for (var song in midiAssetSongs) {
    var bytes = song.toBytes();
    await File('lib/${song.path}').writeAsBytes(bytes);
    print('lib/${song.path}: ${bytes.length} bytes');
  }
}
