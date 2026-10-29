@TestOn('vm')
library;

import 'package:milomedy_midi_engine/setup.dart';
import 'package:test/test.dart';

void main() {
  // Also builds the module that test/web_worklet_test.dart plays in Chrome
  // (run_ci runs the VM tests first).
  test('builds the worklet module once', () async {
    var result = await setupMidiWebWorklet(dir: 'test');
    var segments = result.file.uri.pathSegments;
    expect(segments.sublist(segments.length - 2), [
      'test',
      midiWorkletDefaultUrl,
    ]);
    var module = await result.file.readAsString();
    expect(module, contains("registerProcessor('$midiWorkletProcessorName'"));
    expect(module, isNot(contains('sourceMappingURL')));
    var again = await setupMidiWebWorklet(dir: 'test');
    expect(again.built, isFalse);
    expect(again.version, result.version);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
