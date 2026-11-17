@TestOn('vm')
library;

import 'package:milomedy_sound_fonts/setup.dart';
import 'package:test/test.dart';

void main() {
  // Builds the worker that test/sound_font_worker_web_test.dart runs in
  // Chrome (run_ci runs the VM tests first).
  test('builds the SoundFont worker', () async {
    var result = await setupMidiSoundFontWorker(dir: 'test');
    expect(result.file.existsSync(), isTrue);
    expect(result.file.path, endsWith(midiSoundFontWorkerJsFilename));
    var js = result.file.readAsStringSync();
    expect(js, startsWith('// SoundFont worker of milomedy_sound_fonts'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
