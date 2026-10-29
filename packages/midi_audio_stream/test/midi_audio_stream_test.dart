import 'package:flutter_test/flutter_test.dart';
import 'package:milomedy_midi_audio_stream/midi_audio_stream.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

void main() {
  // flutter test runs without the native library of mp_audio_stream: the
  // example's integration test plays it on a device.
  test('fails cleanly without the native library', () async {
    await expectLater(
      midiCreatePlayer(synths: [MidiSynthSpec.metronome]),
      throwsStateError,
    );
  });
}
