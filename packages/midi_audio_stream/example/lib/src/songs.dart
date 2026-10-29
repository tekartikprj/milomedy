import 'package:milomedy_midi_engine/midi_engine.dart';

/// The tracks: the reeds of an accordion (treble, basses, chords) and the
/// metronome click.
const exampleSynths = [
  MidiSynthSpec(instrument: MidiInstrumentIds.reed, register: 'musette'),
  MidiSynthSpec(instrument: MidiInstrumentIds.reedBass),
  MidiSynthSpec(instrument: MidiInstrumentIds.reedChord),
  MidiSynthSpec.metronome,
];

/// The track of the metronome.
const exampleClickTrack = 3;

/// The tempo the metronome is built at: the tempo set is a speed.
const exampleBaseBpm = 60.0;

/// A measure of clicks at [exampleBaseBpm], on the click track.
MidiTimeline exampleMetronome({int beats = 4}) => midiMetronomeTimeline(
  bpm: exampleBaseBpm,
  beats: beats,
  track: exampleClickTrack,
);

/// A waltz in C: the melody, a bass on beat 1 and a chord on beats 2 and 3.
MidiTimeline exampleWaltz() {
  const beat = 0.4;
  const melody = [64, 67, 72, 71, 67, 65, 64, 62, 60];
  const basses = [48, 43, 48];
  const chords = [
    [52, 55, 60],
    [50, 53, 59],
    [52, 55, 60],
  ];
  return MidiTimeline(
    start: 0,
    notes: [
      for (var (i, key) in melody.indexed)
        MidiTimelineNote(
          start: i * beat,
          duration: beat * (i == melody.length - 1 ? 3 : 0.9),
          key: key,
        ),
      for (var measure = 0; measure < 3; measure++) ...[
        MidiTimelineNote(
          start: measure * 3 * beat,
          duration: beat * 0.8,
          key: basses[measure],
          track: 1,
        ),
        for (var b = 1; b < 3; b++)
          for (var key in chords[measure])
            MidiTimelineNote(
              start: (measure * 3 + b) * beat,
              duration: beat * 0.6,
              key: key,
              track: 2,
            ),
      ],
    ],
  );
}
