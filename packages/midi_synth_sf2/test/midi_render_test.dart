@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../bin/midi_render.dart' as midi_render;

/// A format 0 MIDI file: one note of a beat (96 ticks per beat).
final _song = Uint8List.fromList([
  ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96, //
  ...'MTrk'.codeUnits, 0, 0, 0, 12, //
  0, 0x90, 60, 100, 96, 0x80, 60, 0, 0, 0xff, 0x2f, 0,
]);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('midi_render_test');
  });
  tearDown(() async {
    exitCode = 0;
    await dir.delete(recursive: true);
  });

  test('a sample rate or a speed that is not positive: the usage', () async {
    var song = File('${dir.path}/song.mid');
    await song.writeAsBytes(_song);
    var wav = File('${dir.path}/song.wav');
    for (var arguments in [
      ['--rate', '0'],
      ['--rate', '-5'],
      ['--speed', '0'],
      ['--speed', '-1'],
    ]) {
      exitCode = 0;
      await midi_render.main([...arguments, '-o', wav.path, song.path]);
      expect(exitCode, 64, reason: '$arguments');
      expect(wav.existsSync(), isFalse, reason: '$arguments');
    }
    exitCode = 0;
    await midi_render.main(['--rate', '8000', '-o', wav.path, song.path]);
    expect(exitCode, 0);
    // 0.5 s of song and 0.5 s of tail, 16-bit stereo, a 44 byte header.
    expect(wav.lengthSync(), 44 + 8000 * 4);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
