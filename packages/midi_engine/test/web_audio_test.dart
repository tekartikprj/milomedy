@TestOn('browser')
library;

import 'package:tekartik_midi_engine/midi_engine.dart';
import 'package:tekartik_midi_engine/web_audio.dart';
import 'package:test/test.dart';

void main() {
  test('the Web Audio output plays a metronome', () async {
    var sink = MidiWebAudioSink();
    var player = MidiPlayer(
      sink,
      midiMetronomeEngine(sampleRate: sink.sampleRate),
    );
    var timeline = midiMetronomeTimeline(bpm: 240);
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..setVolume(0, 0.5)
      ..setPan(0, -0.5);
    // Without a user gesture the context may stay suspended: its clock does
    // not move, but the blocks are created and scheduled all the same.
    await player.play().timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {},
    );
    player.pump();
    player.seek(0.5);
    player.pause();
    // Scheduled by hand, whether the context runs or not.
    var engine = midiMetronomeEngine(sampleRate: sink.sampleRate)
      ..load(timeline);
    sink.schedule(sink.currentTime + 0.1, engine.render(2048));
    sink.setTrackMix(0, gain: 0.2, pan: 1);
    sink.cancel();
    await player.close();
  });
}
