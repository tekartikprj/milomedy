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
/// transposition apply, its tuning and speed trainer too; a loop set on it
/// plays until the length is filled. The tracks sending to the reverb
/// ([MidiTrackMix.reverb]) are mixed with the shared reverb of the hosts.
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
  var out = Float32List(total * 2);
  if (mixer.hasReverb) {
    // The mixdown of the hosts, with its shared reverb.
    var mixdown = MidiStereoMixdown(sampleRate: sampleRate)
      ..reverbLevel = mixer.reverbLevel;
    for (var track = 0; track < engine.synths.length; track++) {
      mixdown.setTrack(
        track,
        gain: mixer.gainOf(track),
        pan: mixer.panOf(track),
        reverb: mixer.reverbOf(track),
      );
    }
    var left = Float32List(4096);
    var right = Float32List(4096);
    for (var done = 0; done < total; done += 4096) {
      var frames = total - done < 4096 ? total - done : 4096;
      if (frames < 4096) {
        left = Float32List(frames);
        right = Float32List(frames);
      }
      mixdown.mix(engine.render(frames), left, right);
      for (var i = 0; i < frames; i++) {
        out[2 * (done + i)] = left[i];
        out[2 * (done + i) + 1] = right[i];
      }
    }
    return out;
  }
  var limiter = MidiLimiter(sampleRate: sampleRate);
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
