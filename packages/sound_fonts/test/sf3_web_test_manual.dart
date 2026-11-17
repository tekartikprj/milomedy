// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

/// How long a whole SF3 takes to decompress in a browser, in the page and
/// in the worker, and the longest the page waits meanwhile, by hand: copy
/// it to `.local/benchmark/sound_font.sf3` (GeneralUser GS in SF3 from
/// `tool/compress_sound_font.dart`), run the VM tests (they build
/// test/sound_font_worker.js), then
/// `dart test -p chrome test/sf3_web_test_manual.dart` (dart2js) or with
/// `-c dart2wasm`.
void main() {
  Uint8List? sf3;

  setUpAll(() async {
    var response = await http.get(
      Uri.base.resolve('../.local/benchmark/sound_font.sf3'),
    );
    if (response.statusCode == 200) {
      sf3 = response.bodyBytes;
    }
  });

  /// Runs [decompress] on the SF3, the page's longest pause measured by a
  /// timer every 10 ms.
  Future<void> run(String name, MidiSoundFontDecompressor decompress) async {
    var bytes = sf3;
    if (bytes == null) {
      markTestSkipped('no .local/benchmark/sound_font.sf3');
      return;
    }
    var watch = Stopwatch()..start();
    var longestPause = Duration.zero;
    var last = watch.elapsed;
    var timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      var now = watch.elapsed;
      if (now - last > longestPause) {
        longestPause = now - last;
      }
      last = now;
    });
    var progress = 0;
    var sf2 = await decompress(
      bytes,
      onProgress: (done, total) => progress = done,
    );
    timer.cancel();
    print(
      '$name: ${bytes.length} bytes of SF3 to ${sf2.length} bytes of SF2 in '
      '${watch.elapsedMilliseconds} ms, the page waited at most '
      '${longestPause.inMilliseconds} ms, $progress samples, SHA-256 '
      '${sha256.convert(sf2)}',
    );
  }

  test('decompress a whole SF3 in the page', () async {
    await run('page', midiSoundFontDecompress);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('decompress a whole SF3 in the worker', () async {
    await run(
      'worker',
      midiSoundFontWorkerDecompressor(
        url: 'sound_font_worker.js',
        fallback: false,
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
