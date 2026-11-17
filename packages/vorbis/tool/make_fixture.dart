/// Makes `test/data/sine.ogg`, the fixture of the tests: [sineFrames] of
/// the 440 Hz sine of `test/src/sine.dart` at 22050 Hz, mono, encoded by
/// ffmpeg's libvorbis at quality 4 (bit exact, the same file each time).
///
/// ```sh
/// dart run tool/make_fixture.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:process_run/shell.dart';

import '../test/src/sine.dart';

Future<void> main() async {
  var folder = await Directory.systemTemp.createTemp('milomedy_vorbis_');
  try {
    var raw = File(join(folder.path, 'sine.raw'));
    var data = ByteData(sineFrames * 2);
    var frames = sineSamples();
    for (var i = 0; i < sineFrames; i++) {
      data.setInt16(i * 2, frames[i], Endian.little);
    }
    await raw.writeAsBytes(data.buffer.asUint8List());
    var output = File(join('test', 'data', 'sine.ogg'));
    await Shell(verbose: false).runExecutableArguments('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      '-f',
      's16le',
      '-ar',
      '$sineSampleRate',
      '-ac',
      '1',
      '-i',
      raw.path,
      '-c:a',
      'libvorbis',
      '-q:a',
      '4',
      '-map_metadata',
      '-1',
      '-fflags',
      '+bitexact',
      '-f',
      'ogg',
      output.path,
    ]);
    stdout.writeln('${output.path}: ${await output.length()} bytes');
  } finally {
    await folder.delete(recursive: true);
  }
}
