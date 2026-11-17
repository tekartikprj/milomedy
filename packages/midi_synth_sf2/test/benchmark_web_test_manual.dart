// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../tool/benchmark_lines.dart';

/// The bytes at [url], null when missing.
Future<Uint8List?> _fetch(String url) async {
  var response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    return null;
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

/// The benchmark of `tool/benchmark.dart` in a browser, by hand: copy a
/// SoundFont to `.local/benchmark/sound_font.sf2` and a MIDI file to
/// `.local/benchmark/song.mid`, then
/// `dart test -p chrome test/benchmark_web_test_manual.dart` (dart2js) or
/// with `-c dart2wasm`.
void main() {
  test('benchmark', () async {
    var loading = Stopwatch()..start();
    var soundFontBytes = await _fetch('../.local/benchmark/sound_font.sf2');
    var songBytes = await _fetch('../.local/benchmark/song.mid');
    if (soundFontBytes == null || songBytes == null) {
      markTestSkipped('no .local/benchmark/sound_font.sf2 or song.mid');
      return;
    }
    var soundFont = MidiSoundFont.fromBytes(soundFontBytes);
    var song = MidiSong.fromBytes(songBytes);
    print(
      '${soundFont.name}: loaded in ${loading.elapsedMilliseconds} ms '
      '(fetched too); ${song.notes.length} notes, '
      '${song.duration.toStringAsFixed(1)} s',
    );
    for (var line in midiBenchmark(soundFont, song)) {
      print(line);
    }
  }, timeout: Timeout.none);
}
