/// Offline rendering: a whole timeline to interleaved stereo, as fast as
/// possible (a WAV file, the tests); the same engine, mix, master gain and
/// limiter as the stream output, so what is rendered is what is heard.
library;

import 'dart:typed_data';

import 'engine.dart';
import 'mixer.dart';
import 'timeline.dart';

/// [timeline] rendered by [engine] to interleaved stereo, from its start to
/// its end plus [tail] seconds (the last releases), mixed by [mixer] (each
/// track at full volume in the middle by default). The engine's speed and
/// transposition apply; a loop set on it plays until the length is filled.
Float32List midiRenderOffline(
  MidiEngine engine,
  MidiTimeline timeline, {
  MidiMixer? mixer,
  double tail = 0.5,
}) {
  mixer ??= MidiMixer(engine.synths.length);
  var sampleRate = engine.sampleRate;
  engine.load(timeline);
  var total = ((timeline.duration / engine.speed + tail) * sampleRate).ceil();
  var limiter = MidiLimiter(sampleRate: sampleRate);
  var out = Float32List(total * 2);
  var done = 0;
  while (done < total) {
    var frames = total - done < 4096 ? total - done : 4096;
    var mixed = midiMixStereo(
      engine.render(frames),
      mixer,
      masterGain: midiMasterGain,
    );
    limiter.process(mixed);
    out.setRange(done * 2, done * 2 + mixed.length, mixed);
    done += frames;
  }
  return out;
}
