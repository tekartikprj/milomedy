// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'package:http/http.dart' as http;
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

/// How long a whole SF3 takes to decompress in a browser, by hand: copy it
/// to `.local/benchmark/sound_font.sf3` (GeneralUser GS in SF3 from
/// `tool/compress_sound_font.dart`), then
/// `dart test -p chrome test/sf3_web_test_manual.dart` (dart2js) or with
/// `-c dart2wasm`.
void main() {
  test('decompress a whole SF3', () async {
    var response = await http.get(
      Uri.base.resolve('../.local/benchmark/sound_font.sf3'),
    );
    if (response.statusCode != 200) {
      markTestSkipped('no .local/benchmark/sound_font.sf3');
      return;
    }
    var sf3 = response.bodyBytes;
    var watch = Stopwatch()..start();
    var longestPause = Duration.zero;
    var last = watch.elapsed;
    var sf2 = await midiSoundFontDecompress(
      sf3,
      onProgress: (done, total) {
        var now = watch.elapsed;
        if (now - last > longestPause) {
          longestPause = now - last;
        }
        last = now;
      },
    );
    print(
      '${sf3.length} bytes of SF3 to ${sf2.length} bytes of SF2 in '
      '${watch.elapsedMilliseconds} ms (longest sample '
      '${longestPause.inMilliseconds} ms)',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
