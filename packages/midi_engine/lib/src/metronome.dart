/// A metronome: a timeline of clicks, and the engine that plays it with no
/// asset.
library;

import 'dart:math' as math;

import 'package:tekartik_midi_synth/midi_synth.dart';

import 'engine.dart';
import 'timeline.dart';

/// [measures] measures of [beats] clicks at [bpm], the first of each
/// measure accented, on [track]. On the percussion channel with the General
/// MIDI wood blocks by default, so that a SoundFont plays it as well as the
/// click instrument. Looped over its length, it clicks for ever.
MidiTimeline midiMetronomeTimeline({
  double bpm = 120,
  int beats = 4,
  int measures = 1,
  int track = 0,
  int channel = midiPercussionChannel,
  int accentKey = midiKeyHiWoodBlock,
  int key = midiKeyLowWoodBlock,
  int accentVelocity = 127,
  int velocity = 90,
}) {
  var beat = 60 / bpm;
  var duration = math.min(0.05, beat / 2);
  return MidiTimeline(
    notes: [
      for (var i = 0; i < measures * beats; i++)
        MidiTimelineNote(
          start: i * beat,
          duration: duration,
          key: i % beats == 0 ? accentKey : key,
          velocity: i % beats == 0 ? accentVelocity : velocity,
          track: track,
          channel: channel,
        ),
    ],
    start: 0,
    end: measures * beats * beat,
  );
}

/// An engine of one track playing the clicks of [click] on the percussion
/// channel.
MidiEngine midiMetronomeEngine({
  required int sampleRate,
  ClickInstrument click = const ClickInstrument(),
}) => MidiEngine(
  sampleRate: sampleRate,
  synths: [DartSynth(sampleRate: sampleRate, percussion: click)],
);
