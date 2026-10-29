import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:milomedy_midi_audio_stream/midi_audio_stream.dart';
import 'package:milomedy_midi_audio_stream_example/src/songs.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

/// Plays on the device's output: an isolate feeding mp_audio_stream (or the
/// AudioWorklet on the web).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays the metronome then the waltz', (tester) async {
    await tester.runAsync(() async {
      var player = await midiCreatePlayer(synths: exampleSynths);
      var errors = <String>[];
      player.onError.listen(errors.add);
      var timeline = exampleMetronome();
      player
        ..load(timeline)
        ..setLoop(timeline.start, timeline.end)
        ..speed = 2;
      await player.play();
      await player.sync();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      // 4 beats at 120 bpm: a loop of 2 s of song, 1 s heard.
      expect(player.isPlaying, isTrue);
      expect(player.position, inInclusiveRange(0, 4));
      player
        ..load(exampleWaltz())
        ..speed = 1;
      await player.play();
      await player.sync();
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      // Heard 0.1 s behind what is pushed.
      expect(player.position, closeTo(0.9, 0.3));
      player.pause();
      await player.sync();
      expect(player.state, MidiPlayerState.paused);
      expect(errors, isEmpty);
      await player.close();
    });
  });
}
