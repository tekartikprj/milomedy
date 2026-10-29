@TestOn('vm')
library;

import 'dart:io';

import 'package:milomedy_midi_engine/setup.dart';
import 'package:test/test.dart';

void main() {
  // Builds the module that test/web_worklet_sound_font_test.dart plays in
  // Chrome (run_ci runs the VM tests first): this package is in the package
  // config, so the SoundFont synth is in the worklet.
  test('builds the worklet module with the SoundFont synth', () async {
    var result = await setupMidiWebWorklet(dir: 'test');
    expect(result.file.existsSync(), isTrue);
    var entry = File(
      '.dart_tool/milomedy_midi_engine/web_worklet/midi_worklet_main.dart',
    ).readAsStringSync();
    expect(entry, contains('midiSoundFontRegister();'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
