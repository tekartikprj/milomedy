/// The benchmark of `benchmark.dart`, with no `dart:io`: it also runs in a
/// browser (dart2js, dart2wasm), given the bytes of the files.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

/// The lines of the benchmark of [soundFont] playing [song] (any platform).
List<String> midiBenchmark(MidiSoundFont soundFont, MidiSong song) {
  const rate = 44100;
  var total = (song.duration * rate).round();
  String factor(String name, double seconds) =>
      '$name: ${(song.duration / seconds).toStringAsFixed(1)}x real time '
      '(${seconds.toStringAsFixed(2)} s)';
  var lines = <String>[];
  for (var block in [128, 2048]) {
    var engine = MidiEngine(
      sampleRate: rate,
      synths: [MidiSoundFontSynth(soundFont)],
    )..load(song.toTimeline());
    var stopwatch = Stopwatch()..start();
    for (var done = 0; done < total; done += block) {
      engine.render(block);
    }
    lines.add(
      factor(
        '1 synth, effects, blocks of $block',
        stopwatch.elapsedMicroseconds / 1e6,
      ),
    );
  }
  var timeline = song.toTimeline(trackOf: (_, channel) => channel);
  var sends = midiReverbSends(timeline, trackCount: 16);
  for (var (name, effects, reverb) in [
    ('16 synths, effects', true, false),
    ('16 dry synths', false, false),
    ('16 dry synths + shared reverb', false, true),
  ]) {
    var engine = MidiEngine(
      sampleRate: rate,
      synths: [
        for (var i = 0; i < 16; i++)
          MidiSoundFontSynth(soundFont, reverbAndChorus: effects),
      ],
    )..load(timeline);
    var mixdown = MidiStereoMixdown(sampleRate: rate);
    for (var track = 0; track < 16; track++) {
      mixdown.setTrack(
        track,
        gain: 1,
        pan: 0,
        reverb: reverb ? sends[track] : 0,
      );
    }
    var left = Float32List(128);
    var right = Float32List(128);
    var stopwatch = Stopwatch()..start();
    for (var done = 0; done < total; done += 128) {
      mixdown.mix(engine.render(128), left, right);
    }
    lines.add(
      factor('$name, blocks of 128', stopwatch.elapsedMicroseconds / 1e6),
    );
  }
  return lines;
}
