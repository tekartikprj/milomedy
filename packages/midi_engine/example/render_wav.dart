// ignore_for_file: avoid_print

import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';

/// Writes two WAV files in `.local/`: a metronome (4 measures at 100 bpm)
/// and a tune on accordion reeds (treble, basses, chords) after a measure
/// of count-in clicks.
Future<void> main() async {
  const sampleRate = 44100;
  await Directory('.local').create(recursive: true);

  await _render(
    '.local/metronome.wav',
    midiMetronomeEngine(sampleRate: sampleRate),
    midiMetronomeTimeline(bpm: 100, measures: 4),
  );

  var engine = MidiEngine(
    sampleRate: sampleRate,
    synths: [
      DartSynth(
        sampleRate: sampleRate,
        instrument: ReedInstrument.treble(
          register: ReedRegister.byId('musette'),
        ),
      ),
      DartSynth(sampleRate: sampleRate, instrument: ReedInstrument.bass()),
      DartSynth(sampleRate: sampleRate, instrument: ReedInstrument.chord()),
      DartSynth(sampleRate: sampleRate, percussion: const ClickInstrument()),
    ],
  );
  await _render('.local/tune.wav', engine, _tune());
}

/// A waltz in C: the melody on track 0, a bass on beat 1 (track 1) and a
/// chord on beats 2 and 3 (track 2), after 3 clicks (track 3).
MidiTimeline _tune() {
  const beat = 0.4;
  const melody = [64, 67, 72, 71, 67, 65, 64, 62, 60];
  const basses = [48, 43, 48];
  const chords = [
    [52, 55, 60],
    [50, 53, 59],
    [52, 55, 60],
  ];
  var start = 3 * beat;
  return MidiTimeline(
    start: 0,
    notes: [
      for (var i = 0; i < 3; i++)
        MidiTimelineNote(
          start: i * beat,
          duration: 0.05,
          key: i == 0 ? midiKeyHiWoodBlock : midiKeyLowWoodBlock,
          track: 3,
          channel: midiPercussionChannel,
        ),
      for (var (i, key) in melody.indexed)
        MidiTimelineNote(
          start: start + i * beat,
          duration: beat * (i == melody.length - 1 ? 3 : 0.9),
          key: key,
        ),
      for (var measure = 0; measure < 3; measure++) ...[
        MidiTimelineNote(
          start: start + measure * 3 * beat,
          duration: beat * 0.8,
          key: basses[measure],
          track: 1,
        ),
        for (var b = 1; b < 3; b++)
          for (var key in chords[measure])
            MidiTimelineNote(
              start: start + (measure * 3 + b) * beat,
              duration: beat * 0.6,
              key: key,
              track: 2,
            ),
      ],
    ],
  );
}

/// Renders [timeline] with [engine] to the WAV file [path].
Future<void> _render(
  String path,
  MidiEngine engine,
  MidiTimeline timeline,
) async {
  var stopwatch = Stopwatch()..start();
  var samples = midiRenderOffline(engine, timeline);
  var elapsed = stopwatch.elapsed;
  var sampleRate = engine.sampleRate;
  await File(path).writeAsBytes(midiWavBytes(samples, sampleRate: sampleRate));
  var seconds = samples.length / 2 / sampleRate;
  print(
    '$path: ${seconds.toStringAsFixed(1)} s rendered in '
    '${elapsed.inMilliseconds} ms',
  );
}
