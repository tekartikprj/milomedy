import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tekartik_midi_engine/midi_engine.dart';
import 'package:tekartik_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 8000;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// The first frame of [samples] above [threshold].
int _onset(List<double> samples, [double threshold = 1e-6]) {
  for (var i = 0; i < samples.length; i++) {
    if (samples[i].abs() > threshold) {
      return i;
    }
  }
  return -1;
}

/// The peak of [samples] once the releases of the notes before have ended.
double _peakAfterReleases(List<double> samples) =>
    _peak(samples.sublist(_rate ~/ 10));

/// The frames where a sound starts after at least [gap] silent frames.
List<int> _onsets(List<double> samples, {int gap = 100}) {
  var onsets = <int>[];
  var silent = gap;
  for (var i = 0; i < samples.length; i++) {
    if (samples[i].abs() > 1e-6) {
      if (silent >= gap) {
        onsets.add(i);
      }
      silent = 0;
    } else {
      silent++;
    }
  }
  return onsets;
}

/// An engine of two reed tracks (a treble, a bass) and a click track.
MidiEngine _engine() => MidiEngine(
  sampleRate: _rate,
  synths: [
    DartSynth(sampleRate: _rate, instrument: ReedInstrument.treble()),
    DartSynth(sampleRate: _rate, instrument: ReedInstrument.bass()),
    DartSynth(sampleRate: _rate, percussion: const ClickInstrument()),
  ],
);

/// Quarter notes at 60 bpm on track 0: one per second.
MidiTimeline _scale(List<int> keys, {double start = 0}) => MidiTimeline(
  notes: [
    for (var (i, key) in keys.indexed)
      MidiTimelineNote(start: start + i.toDouble(), duration: 0.9, key: key),
  ],
);

void main() {
  group('timeline', () {
    test('sorted, stable, its bounds', () {
      var timeline = MidiTimeline(
        notes: const [
          MidiTimelineNote(start: 1, duration: 1, key: 62),
          MidiTimelineNote(start: 0, duration: 0.5, key: 60, track: 2),
          MidiTimelineNote(start: 1, duration: 3, key: 64),
        ],
        messages: const [
          MidiTimelineMessage(time: 5, status: midiProgramChange, data1: 1),
          MidiTimelineMessage(time: -1, status: midiProgramChange, data1: 2),
        ],
      );
      expect([for (var note in timeline.notes) note.key], [60, 62, 64]);
      expect(timeline.messages.first.data1, 2);
      expect(timeline.start, -1);
      expect(timeline.end, 5);
      expect(timeline.duration, 6);
      expect(timeline.trackCount, 3);
      var bounded = MidiTimeline(notes: timeline.notes, start: 0, end: 2);
      expect(bounded.end, 2);
      expect(MidiTimeline().trackCount, 0);
    });
  });

  group('engine', () {
    test('a note starts at its frame, on its track', () {
      var engine = _engine()
        ..load(
          MidiTimeline(
            notes: const [
              MidiTimelineNote(start: 0.5, duration: 0.25, key: 60),
              MidiTimelineNote(start: 0.25, duration: 0.25, key: 36, track: 1),
            ],
          ),
        );
      var block = engine.render(_rate);
      expect(_onset(block.left[0]), _rate ~/ 2);
      expect(_onset(block.left[1]), _rate ~/ 4);
      expect(_peak(block.left[2]), 0);
      expect(block.right[0], block.left[0]);
      expect(block.songStart, 0);
      expect(engine.position, closeTo(1, 1e-9));
    });

    test('exact frames, across renders of any size', () {
      var timeline = MidiTimeline(
        notes: [
          for (var i = 0; i < 8; i++)
            MidiTimelineNote(start: 0.1 + i * 0.13, duration: 0.01, key: 60),
        ],
      );
      var engine = _engine()..load(timeline);
      var samples = <double>[];
      for (var size in [100, 37, 1000, 1, 4000, 3000]) {
        samples.addAll(engine.render(size).left[0]);
      }
      expect(_onsets(samples), [
        for (var i = 0; i < 8; i++) ((0.1 + i * 0.13) * _rate).round(),
      ]);
    });

    test('deterministic, in range', () {
      var timeline = _scale([60, 64, 67, 72]);
      var a = midiRenderOffline(_engine(), timeline);
      var b = midiRenderOffline(_engine(), timeline);
      expect(a, b);
      var peak = _peak(a);
      expect(peak, greaterThan(0.05));
      expect(peak, lessThanOrEqualTo(midiLimit));
      expect(a.any((s) => s.isNaN), isFalse);
      expect(a.length, ((timeline.duration + 0.5) * _rate).ceil() * 2);
    });

    test('fingerprint (the same samples on every platform)', () {
      var timeline = MidiTimeline(
        notes: [
          const MidiTimelineNote(start: 0, duration: 0.6, key: 64),
          const MidiTimelineNote(start: 0, duration: 0.9, key: 40, track: 1),
          const MidiTimelineNote(
            start: 0.5,
            duration: 0.05,
            key: midiKeyHiWoodBlock,
            track: 2,
            channel: midiPercussionChannel,
          ),
        ],
      );
      var engine = _engine();
      (engine.synths[0] as DartSynth).instrument = ReedInstrument.treble(
        register: ReedRegister.byId('musette'),
      );
      var samples = midiRenderOffline(engine, timeline);
      var fingerprint = [
        for (var i = 0; i < samples.length; i += 499) samples[i],
      ];
      expect(fingerprint, hasLength(_fingerprint.length));
      for (var i = 0; i < fingerprint.length; i++) {
        expect(fingerprint[i], closeTo(_fingerprint[i], 1e-5), reason: '$i');
      }
    });

    test('loop', () {
      var engine = _engine()
        ..load(_scale([60, 62, 64, 65, 67, 69]))
        ..setLoop(2, 4);
      // 0..2, then 2..4 three times.
      engine.render(_rate * 2);
      expect(engine.position, closeTo(2, 1e-9));
      for (var i = 0; i < 3; i++) {
        expect(engine.framesToLoopEnd, _rate * 2);
        var block = engine.render(_rate * 2);
        expect(block.songStart, closeTo(2, 1e-9));
        expect(_onset(block.left[0]), 0);
      }
      expect(engine.ended, isFalse);
      engine.setLoop(null, null);
      expect(engine.framesToLoopEnd, isNull);
      engine.render(_rate * 5);
      expect(engine.ended, isTrue);
    });

    test('a loop does not play the note at its end', () {
      var engine = _engine()
        ..load(_scale([60, 62]))
        ..setLoop(0, 1);
      for (var i = 0; i < 3; i++) {
        var block = engine.render(_rate);
        // The first note, released before the end: the second never starts.
        expect(_peak(block.left[0].sublist(_rate - 10)), 0);
      }
    });

    test('seek restarts the notes sounding', () {
      var engine = _engine()
        ..load(
          MidiTimeline(
            notes: const [MidiTimelineNote(start: 0, duration: 4, key: 60)],
          ),
        )
        ..seek(1.5);
      var block = engine.render(_rate ~/ 2);
      expect(_onset(block.left[0]), 0);
      expect(block.songStart, 1.5);
      // Too close to its end: not restarted.
      engine.seek(3.95);
      expect(_peakAfterReleases(engine.render(_rate ~/ 2).left[0]), 0);
    });

    test('seek sends the messages before it again', () {
      // Program 1 (the only one with a sound) from 1 s, volume 0 from 3 s.
      var synth = DartSynth(
        sampleRate: _rate,
        programs: {1: ReedInstrument.chord()},
      );
      var engine = MidiEngine(sampleRate: _rate, synths: [synth])
        ..load(
          MidiTimeline(
            notes: const [MidiTimelineNote(start: 0, duration: 5, key: 60)],
            messages: const [
              MidiTimelineMessage(time: 1, status: midiProgramChange, data1: 1),
              MidiTimelineMessage(
                time: 3,
                status: midiControlChange,
                data1: midiControllerVolume,
              ),
            ],
          ),
        );
      expect(_peak(engine.render(_rate ~/ 2).left[0]), 0);
      engine.seek(2);
      expect(_peak(engine.render(_rate ~/ 2).left[0]), greaterThan(0.01));
      engine.seek(3.5);
      expect(_peakAfterReleases(engine.render(_rate ~/ 2).left[0]), 0);
      // Back before the volume change: the default volume again.
      engine.seek(2);
      expect(_peak(engine.render(_rate ~/ 2).left[0]), greaterThan(0.01));
      // Back before the program change: silent again.
      engine.seek(0.5);
      expect(_peakAfterReleases(engine.render(_rate ~/ 4).left[0]), 0);
    });

    test('replace keeps the place in the music', () {
      var engine = _engine()..load(_scale([60, 62, 64, 65]));
      engine.render(_rate * 2);
      engine.replace(_scale([72, 74, 76, 77]));
      expect(engine.position, closeTo(2, 1e-9));
      expect(_onset(engine.render(_rate ~/ 2).left[0]), 0);
    });

    test('speed', () {
      var engine = _engine()
        ..load(
          MidiTimeline(
            notes: const [
              MidiTimelineNote(start: 0, duration: 0.5, key: 60),
              MidiTimelineNote(start: 1, duration: 0.5, key: 62),
            ],
          ),
        )
        ..speed = 2;
      var block = engine.render(_rate);
      expect(block.speed, 2);
      // The second note, at 1 s of song: half a second.
      expect(_onsets(block.left[0]), [0, _rate ~/ 2]);
      expect(engine.position, closeTo(2, 1e-9));
      expect(() => engine.speed = 0, throwsArgumentError);
    });

    test('transpose, not the percussion', () {
      var synth = DartSynth(
        sampleRate: _rate,
        instrument: ReedInstrument.chord(),
        percussion: const ClickInstrument(),
      );
      var engine = MidiEngine(sampleRate: _rate, synths: [synth]);
      double crossingsPerSecond(MidiTimelineNote note) {
        engine.load(MidiTimeline(notes: [note]));
        var samples = engine.render(_rate ~/ 2).left[0];
        var crossings = 0;
        for (var i = 1; i < samples.length; i++) {
          if ((samples[i - 1] < 0) != (samples[i] < 0)) {
            crossings++;
          }
        }
        return crossings * 2.0;
      }

      const a3 = MidiTimelineNote(start: 0, duration: 1, key: 57);
      const click = MidiTimelineNote(
        start: 0,
        duration: 1,
        key: midiKeyHiWoodBlock,
        channel: midiPercussionChannel,
      );
      var plain = crossingsPerSecond(a3);
      var clickPlain = crossingsPerSecond(click);
      engine.transpose = 12;
      expect(crossingsPerSecond(a3), closeTo(plain * 2, plain * 0.1));
      expect(crossingsPerSecond(click), clickPlain);
    });

    test('a transposition while a note sounds releases the key played', () {
      var engine = _engine()..load(_scale([60]));
      engine.render(_rate ~/ 2);
      engine.transpose = 3;
      engine.render(_rate);
      expect(engine.synths[0].activeVoiceCount, 0);
      expect(engine.ended, isTrue);
    });

    test('the same key again restarts it', () {
      var engine = _engine()
        ..load(
          MidiTimeline(
            notes: const [
              MidiTimelineNote(start: 0, duration: 2, key: 60),
              MidiTimelineNote(start: 0.5, duration: 0.5, key: 60),
            ],
          ),
        );
      engine.render(_rate);
      // The first one released at 0.5 s, the second one ends at 1 s.
      engine.render(_rate ~/ 10);
      expect(engine.synths[0].activeVoiceCount, 0);
      // Nothing more at the end of the first one.
      expect(_peak(engine.render(_rate).left[0]), 0);
      expect(engine.ended, isTrue);
    });

    test('ended waits for the releases', () {
      var engine = _engine()..load(_scale([60]));
      engine.render((0.91 * _rate).round());
      expect(engine.ended, isFalse);
      engine.render(_rate ~/ 10);
      expect(engine.ended, isTrue);
      expect(MidiEngine(sampleRate: _rate, synths: []).ended, isTrue);
    });

    test('a synth at another sample rate', () {
      expect(
        () => MidiEngine(
          sampleRate: _rate,
          synths: [DartSynth(sampleRate: 44100)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('mixer', () {
    test('mute and solo', () {
      var mixer = MidiMixer(3);
      mixer.tracks[0].volume = 0.5;
      expect(mixer.gainOf(0), 0.5);
      expect(mixer.gainOf(5), 1);
      mixer.tracks[1].solo = true;
      expect(mixer.gainOf(0), 0);
      expect(mixer.gainOf(1), 1);
      mixer.tracks[1].mute = true;
      expect(mixer.gainOf(1), 0);
    });

    test('pan, as Web Audio', () {
      var middle = midiStereoPan(0);
      expect(middle.leftToLeft, 1);
      expect(middle.rightToLeft, closeTo(0, 1e-9));
      expect(middle.rightToRight, 1);
      var left = midiStereoPan(-1);
      expect(left.rightToLeft, 1);
      expect(left.rightToRight, closeTo(0, 1e-9));
      var right = midiStereoPan(2);
      expect(right.leftToRight, 1);
      expect(right.leftToLeft, closeTo(0, 1e-9));
    });

    test('mix', () {
      var block = MidiRenderBlock(
        [
          Float32List.fromList([1, 1]),
          Float32List.fromList([0.5, 0.5]),
        ],
        [
          Float32List.fromList([1, 1]),
          Float32List.fromList([0.5, 0.5]),
        ],
        2,
        0,
      );
      var mixer = MidiMixer(2);
      mixer.tracks[0].pan = 1;
      mixer.tracks[1].volume = 0.5;
      var stereo = midiMixStereo(block, mixer, masterGain: 0.5);
      // Track 0 all to the right, track 1 in the middle.
      expect(stereo[0], closeTo(0.125, 1e-6));
      expect(stereo[1], closeTo(1 + 0.125, 1e-6));
    });

    test('limiter', () {
      var limiter = MidiLimiter(sampleRate: _rate);
      var frames = Float32List(2000)..fillRange(0, 2000, 1);
      limiter.process(frames);
      expect(_peak(frames), lessThanOrEqualTo(midiLimit + 1e-6));
      var quiet = Float32List(2 * _rate)..fillRange(0, 2 * _rate, 0.1);
      limiter.process(quiet);
      // The gain back to 1.
      expect(quiet.last, closeTo(0.1, 1e-3));
    });
  });

  group('metronome', () {
    test('clicks on the beats, the first accented, for ever', () {
      var timeline = midiMetronomeTimeline(bpm: 120, beats: 3);
      expect(timeline.notes, hasLength(3));
      expect(timeline.duration, 1.5);
      expect(timeline.notes.first.key, midiKeyHiWoodBlock);
      expect(timeline.notes.last.key, midiKeyLowWoodBlock);
      var engine = midiMetronomeEngine(sampleRate: _rate)
        ..load(timeline)
        ..setLoop(timeline.start, timeline.end);
      var samples = engine.render(6 * _rate).left[0];
      // A sine: its first sample is 0.
      expect(_onsets(samples), [
        for (var i = 0; i < 12; i++) i * _rate ~/ 2 + 1,
      ]);
      // The accent, louder.
      expect(
        _peak(samples.sublist(0, 400)),
        greaterThan(_peak(samples.sublist(_rate ~/ 2, _rate ~/ 2 + 400))),
      );
      expect(engine.ended, isFalse);
    });

    test('measures, tempo', () {
      var timeline = midiMetronomeTimeline(bpm: 60, measures: 2);
      expect(timeline.notes, hasLength(8));
      expect(timeline.notes[4].key, midiKeyHiWoodBlock);
      expect(timeline.end, 8);
    });
  });

  test('wav', () {
    var bytes = midiWavBytes(
      Float32List.fromList([0, 1, -1, 2]),
      sampleRate: 8000,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(bytes.length, 44 + 8);
    var data = ByteData.sublistView(bytes);
    expect(data.getInt16(46, Endian.little), 32767);
    expect(data.getInt16(48, Endian.little), -32767);
    expect(data.getInt16(50, Endian.little), 32767);
  });
}

/// Every 499th sample of the fingerprint render, on the VM.
const _fingerprint = <double>[
  0.00027207,
  0.06044764,
  -0.03708363,
  0.00097058,
  -0.04044524,
  -0.05944430,
  0.12145379,
  0.06089481,
  -0.04232749,
  -0.00793285,
  -0.00099476,
  -0.02758454,
  0.04954713,
  -0.06630330,
  0.08261806,
  -0.06358908,
  -0.00683742,
  0.05617605,
  -0.02316506,
  0.09926634,
  -0.04088075,
  -0.00667394,
  0.00461800,
  0.02474227,
  0.03127927,
  -0.04913976,
  0.05562545,
  -0.01611241,
  -0.00630720,
  0.00765782,
  0.00967067,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
  0.00000000,
];
