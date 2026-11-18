import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/zoned_sound_font.dart';

/// [timeline] rendered with the SoundFont [bytes] (one synth, track 0).
Float32List render(
  Uint8List bytes,
  MidiTimeline timeline, {
  int transpose = 0,
}) {
  var engine = MidiEngine(
    sampleRate: 44100,
    synths: [MidiSoundFontSynth(MidiSoundFont.fromBytes(bytes))],
  )..transpose = transpose;
  return midiRenderOffline(engine, timeline);
}

MidiTimelineNote note(
  double start,
  int key, {
  int channel = 0,
  int velocity = 100,
  double duration = 0.3,
}) => MidiTimelineNote(
  start: start,
  duration: duration,
  key: key,
  velocity: velocity,
  channel: channel,
);

/// A song of the zoned SoundFont: the piano soft and loud, the lead, the
/// kit.
MidiTimeline song() => MidiTimeline(
  notes: [
    note(0, 40),
    note(0.1, 70, velocity: 30),
    note(0.2, 72, velocity: 90, duration: 0.6),
    note(0.4, 60, channel: 1),
    note(0.5, 36, channel: 9),
    note(0.6, 42, channel: 9),
  ],
  messages: [const MidiTimelineMessage(time: 0, status: 0xc1, data1: 5)],
);

/// [actual] is [expected], within a float32 rounding (the samples at another
/// place in the sample data: the positions, then the interpolation, round
/// differently).
void expectSameSound(Float32List actual, Float32List expected) {
  expect(actual.length, expected.length);
  var difference = 0.0;
  for (var i = 0; i < actual.length; i++) {
    var d = (actual[i] - expected[i]).abs();
    if (d > difference) {
      difference = d;
    }
  }
  expect(difference, lessThan(1e-6));
}

double peak(Float32List samples) =>
    samples.fold(0.0, (peak, s) => s.abs() > peak ? s.abs() : peak);

void main() {
  group('MidiSoundFontLocalSampler', () {
    test('the SoundFont of a song plays as the whole one', () async {
      var bytes = zonedSoundFontBytes();
      var sampler = MidiSoundFontLocalSampler(bytes);
      var timeline = song();
      var samples = sampler.samplesOf(timeline);
      expect(samples, {0, 1, 2, 3, 4, 5});
      var sf2 = await sampler.soundFont(samples);
      var expected = render(bytes, timeline);
      expect(peak(expected), greaterThan(0.01));
      expectSameSound(render(sf2, timeline), expected);
    });

    test('only its samples: the others silent, the song the same', () async {
      var bytes = zonedSoundFontBytes();
      var sampler = MidiSoundFontLocalSampler(bytes);
      // The piano low and the kick only.
      var timeline = MidiTimeline(
        notes: [note(0, 40), note(0.2, 36, channel: 9)],
      );
      var samples = sampler.samplesOf(timeline);
      expect(samples, {0, 3});
      var sf2 = await sampler.soundFont(samples);
      expect(sf2.length, lessThan(bytes.length));
      expectSameSound(render(sf2, timeline), render(bytes, timeline));
      // A note whose sample is not there: silent.
      var other = MidiTimeline(notes: [note(0, 70, velocity: 30)]);
      expect(peak(render(bytes, other)), greaterThan(0.001));
      expect(peak(render(sf2, other)), 0);
      // The definition stays whole.
      expect(
        MidiSoundFont.fromBytes(sf2).presets.length,
        MidiSoundFont.fromBytes(bytes).presets.length,
      );
    });

    test('transposed: the samples of the keys played', () async {
      var bytes = zonedSoundFontBytes();
      var sampler = MidiSoundFontLocalSampler(bytes);
      // Key 55 is the low sample, 55 + 7 a high one.
      var timeline = MidiTimeline(notes: [note(0, 55, velocity: 30)]);
      expect(sampler.samplesOf(timeline), {0});
      var samples = sampler.samplesOf(timeline, transpose: 7);
      expect(samples, {1});
      expect(sampler.samplesOf(timeline, margin: 7), {0, 1});
      expect(sampler.samplesOf(timeline, transpose: 7, margin: 1), {1});
      var sf2 = await sampler.soundFont(samples);
      expectSameSound(
        render(sf2, timeline, transpose: 7),
        render(bytes, timeline, transpose: 7),
      );
    });

    test('no sample: a SoundFont the synth loads, silent', () async {
      var bytes = zonedSoundFontBytes();
      var sf2 = await MidiSoundFontLocalSampler(bytes).soundFont(const []);
      expect(peak(render(sf2, song())), 0);
    });

    test('an SF3: its samples decoded, played as its SF2', () async {
      var sf3 = midiTinySoundFontSf3Bytes();
      var sf2 = await midiSoundFontDecompress(sf3);
      var sampler = MidiSoundFontLocalSampler(sf3);
      var timeline = MidiTimeline(
        notes: [note(0, 69, duration: 0.5), note(0.2, 38, channel: 9)],
      );
      var samples = sampler.samplesOf(timeline);
      expect(samples, {0, 1});
      var expected = render(sf2, timeline);
      expect(peak(expected), greaterThan(0.01));
      expectSameSound(
        render(await sampler.soundFont(samples), timeline),
        expected,
      );
      // The sine only: the noise left out.
      var sine = MidiTimeline(notes: [note(0, 69, duration: 0.5)]);
      expectSameSound(
        render(await sampler.soundFont(sampler.samplesOf(sine)), sine),
        render(sf2, sine),
      );
    });

    test('the frames kept: the last used, within cacheBytes', () async {
      var bytes = zonedSoundFontBytes();
      // Room for about one sample (200 to 400 frames, 2 bytes each).
      var sampler = MidiSoundFontLocalSampler(bytes, cacheBytes: 700);
      await sampler.soundFont([0, 3]);
      // Those of the last SoundFont made are kept, whatever their size.
      expect(sampler.decoded.toSet(), {0, 3});
      await sampler.soundFont([1]);
      expect(sampler.decoded.toSet(), {1});
      sampler = MidiSoundFontLocalSampler(bytes);
      await sampler.soundFont([0, 3]);
      await sampler.soundFont([1]);
      // The least recently used first.
      expect(sampler.decoded.toList(), [0, 3, 1]);
      await sampler.soundFont([0]);
      expect(sampler.decoded.toList(), [3, 1, 0]);
      await sampler.close();
      expect(sampler.decoded, isEmpty);
    });

    test('a sample that is not there: a RangeError', () async {
      var sampler = MidiSoundFontLocalSampler(zonedSoundFontBytes());
      await expectLater(sampler.soundFont([6]), throwsRangeError);
      // Still usable.
      expect(await sampler.soundFont([0]), isNotEmpty);
    });

    test('not a SoundFont: a FormatException', () {
      expect(
        () => MidiSoundFontLocalSampler(Uint8List(64)),
        throwsFormatException,
      );
    });

    test('midiSoundFontSampler: in this isolate on io', () async {
      var sampler = await midiSoundFontSampler(zonedSoundFontBytes());
      expect(sampler, isA<MidiSoundFontLocalSampler>());
      expect(sampler.definition.name, 'Zoned test SoundFont');
    }, testOn: 'vm');
  });
}
