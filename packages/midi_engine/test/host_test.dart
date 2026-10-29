import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 8000;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

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

/// A host and what it sends, rendered in blocks of 128 frames as an
/// AudioWorklet does.
class _Host {
  final events = <Map<String, Object?>>[];
  late final MidiEngineHost host;
  var frame = 0;

  _Host(List<MidiSynthSpec> synths) {
    host = MidiEngineHost(
      sampleRate: _rate,
      synths: synths,
      send: events.add,
      reportFrames: 1024,
    );
  }

  void command(String type, [Map<String, Object?> values = const {}]) =>
      host.handle({'type': type, ...values});

  /// Renders [seconds], the left channel.
  List<double> render(double seconds) {
    var samples = <double>[];
    for (var i = 0; i < (seconds * _rate / 128).round(); i++) {
      var left = Float32List(128);
      var right = Float32List(128);
      host.render(left, right, frame / _rate);
      frame += 128;
      expect(right, left);
      samples.addAll(left);
    }
    return samples;
  }

  Iterable<Map<String, Object?>> ofType(String type) =>
      events.where((event) => event['type'] == type);

  String? get lastState =>
      ofType(MidiHostEvents.state).lastOrNull?['state'] as String?;
}

/// A support whose SoundFont is the number of its bytes.
class _FakeSupport implements MidiSoundFontSupport {
  @override
  Object parse(Uint8List bytes) => bytes.length;

  @override
  MidiSynth synth(Object soundFont, int sampleRate) =>
      _FakeSynth(soundFont as int, sampleRate);
}

/// The click instrument, remembering its program changes.
class _FakeSynth extends DartSynth {
  final int soundFont;
  final programChanges = <int>[];

  _FakeSynth(this.soundFont, int sampleRate)
    : super(sampleRate: sampleRate, percussion: const ClickInstrument());

  @override
  void send(int status, int data1, [int data2 = 0]) {
    if (status & 0xf0 == midiProgramChange) {
      programChanges.add(data1);
    }
    super.send(status, data1, data2);
  }
}

/// A click a second on track 0, for 4 s.
MidiTimeline _clicks() => midiMetronomeTimeline(bpm: 60, beats: 4);

void main() {
  group('protocol', () {
    test('a timeline and back', () {
      var timeline = MidiTimeline(
        notes: const [
          MidiTimelineNote(start: -0.5, duration: 1, key: 60, velocity: 90),
          MidiTimelineNote(
            start: 1.25,
            duration: 0.5,
            key: 76,
            track: 3,
            channel: 9,
          ),
        ],
        messages: const [
          MidiTimelineMessage(
            time: 0.5,
            status: midiControlChange | 2,
            data1: midiControllerVolume,
            data2: 64,
            track: 1,
          ),
        ],
        end: 10,
      );
      var copy = midiTimelineFromMap(midiTimelineToMap(timeline));
      expect(copy.start, -0.5);
      expect(copy.end, 10);
      expect(
        copy.notes.map((note) => '$note'),
        timeline.notes.map((n) => '$n'),
      );
      expect(copy.notes.first.velocity, 90);
      expect(
        copy.messages.map((message) => '$message'),
        timeline.messages.map((message) => '$message'),
      );
    });

    test('synth specs', () {
      const spec = MidiSynthSpec(
        instrument: MidiInstrumentIds.reed,
        register: 'musette',
        percussion: MidiInstrumentIds.click,
      );
      expect(MidiSynthSpec.fromMap(spec.toMap()), spec);
      var synth = spec.build(_rate) as DartSynth;
      expect(
        (synth.instrument! as ReedInstrument).ranks,
        ReedRegister.byId('musette').ranks,
      );
      expect(synth.percussion, isA<ClickInstrument>());
      const MidiSynthSpec(
        instrument: MidiInstrumentIds.reedBass,
      ).applyTo(synth);
      expect((synth.instrument! as ReedInstrument).timbre, ReedTimbre.bass);
      expect(synth.percussion, isNull);
      expect(
        (MidiSynthSpec.metronome.build(_rate) as DartSynth).instrument,
        isNull,
      );
      const soundFont = MidiSynthSpec(soundFont: 'gm');
      expect(MidiSynthSpec.fromMap(soundFont.toMap()), soundFont);
      expect(soundFont.build(_rate), isA<MidiDeferredSynth>());
    });
  });

  group('SoundFont tracks', () {
    tearDown(() => midiSoundFontSupport = null);

    test('silent until loaded, an error without support', () {
      var host = _Host([const MidiSynthSpec(soundFont: 'gm')]);
      host
        ..command(MidiHostCommands.load, {
          'timeline': midiTimelineToMap(_clicks()),
        })
        ..command(MidiHostCommands.play);
      expect(_peak(host.render(0.5)), 0);
      host.command(MidiHostCommands.soundFont, {
        'id': 'gm',
        'bytes': Uint8List(4),
      });
      expect(
        host.ofType(MidiHostEvents.error).single['message'],
        contains('midiSoundFontRegister'),
      );
    });

    test('loaded: the tracks playing it get their synth', () {
      // A fake support: the "SoundFont" is its size, its synth the click.
      midiSoundFontSupport = _FakeSupport();
      var host = _Host([
        const MidiSynthSpec(soundFont: 'gm'),
        const MidiSynthSpec(soundFont: 'other'),
      ]);
      var timeline = MidiTimeline(
        notes: [
          for (var track = 0; track < 2; track++)
            for (var beat = 0; beat < 4; beat++)
              MidiTimelineNote(
                start: beat.toDouble(),
                duration: 0.1,
                key: midiKeyHiWoodBlock,
                track: track,
                channel: midiPercussionChannel,
              ),
        ],
        messages: const [
          // Chased once the synth is set.
          MidiTimelineMessage(
            time: 0,
            status: midiProgramChange | midiPercussionChannel,
            data1: 7,
          ),
        ],
      );
      host
        ..command(MidiHostCommands.load, {
          'timeline': midiTimelineToMap(timeline),
        })
        ..command(MidiHostCommands.play)
        ..render(0.5)
        ..command(MidiHostCommands.soundFont, {
          'id': 'gm',
          'bytes': Uint8List(10),
        });
      var synth = host.host.engine.synths[0] as MidiDeferredSynth;
      expect(synth.synth, isA<_FakeSynth>());
      expect((synth.synth! as _FakeSynth).soundFont, 10);
      expect((host.host.engine.synths[1] as MidiDeferredSynth).synth, isNull);
      // The clicks of track 0 from the next beat (at 1 s, 31 blocks of 128
      // frames played), the program sent again.
      expect(_onsets(host.render(1)), [_rate - 31 * 128 + 1]);
      expect((synth.synth! as _FakeSynth).programChanges, contains(7));
      expect(host.ofType(MidiHostEvents.error), isEmpty);
    });
  });

  group('host', () {
    test('plays in blocks, reports its state and position', () {
      var host = _Host([MidiSynthSpec.metronome]);
      expect(_peak(host.render(0.1)), 0);
      host.command(MidiHostCommands.load, {
        'timeline': midiTimelineToMap(_clicks()),
      });
      expect(host.lastState, 'stopped');
      host.command(MidiHostCommands.play);
      expect(host.lastState, 'playing');
      var samples = host.render(2.5);
      // A sine: its first sample is 0.
      expect(_onsets(samples), [1, _rate + 1, 2 * _rate + 1]);
      var reports = host.ofType(MidiHostEvents.position).toList();
      expect(reports.length, greaterThan(15));
      // The song position at the time of the block: played from the 6th
      // block (768 frames).
      var report = reports[3];
      expect(
        (report['time']! as double) - (report['position']! as double),
        closeTo(768 / _rate, 1e-9),
      );
      expect(report['speed'], 1);
    });

    test('pause fades out, then plays on from there', () {
      var host = _Host([MidiSynthSpec.metronome]);
      host
        ..command(MidiHostCommands.load, {
          'timeline': midiTimelineToMap(
            MidiTimeline(
              notes: const [MidiTimelineNote(start: 0, duration: 4, key: 60)],
            ),
          ),
        })
        ..command(MidiHostCommands.synth, {
          'track': 0,
          'spec': const MidiSynthSpec(
            instrument: MidiInstrumentIds.reedChord,
          ).toMap(),
        })
        ..command(MidiHostCommands.play);
      host.render(0.5);
      host.command(MidiHostCommands.pause);
      expect(host.lastState, 'playing');
      // 5 ms, then silence.
      var fading = host.render(0.016);
      expect(_peak(fading.sublist(0, 20)), greaterThan(0.01));
      expect(_peak(fading.sublist(40)), 0);
      expect(host.lastState, 'paused');
      var paused = host.ofType(MidiHostEvents.state).last;
      // Where the pause came: 31 blocks.
      expect(paused['position'], closeTo(31 * 128 / _rate, 1e-9));
      expect(_peak(host.render(0.2)), 0);
      // The note sounding there starts again.
      host.command(MidiHostCommands.play);
      expect(_onsets(host.render(0.2)), [0]);
    });

    test('stop, seek, the end', () {
      var host = _Host([MidiSynthSpec.metronome]);
      host
        ..command(MidiHostCommands.load, {
          'timeline': midiTimelineToMap(_clicks()),
        })
        ..command(MidiHostCommands.seek, {'position': 2.5});
      expect(host.lastState, 'paused');
      host.command(MidiHostCommands.play);
      // The clicks at 3 s, then the end.
      expect(_onsets(host.render(2)), [_rate ~/ 2 + 1]);
      expect(host.lastState, 'stopped');
      expect(host.ofType(MidiHostEvents.state).last['position'], 0);
      host
        ..command(MidiHostCommands.play)
        ..render(0.5)
        ..command(MidiHostCommands.stop);
      host.render(0.1);
      expect(host.lastState, 'stopped');
      expect(_peak(host.render(0.5)), 0);
    });

    test('loop, speed, mix', () {
      var host = _Host([MidiSynthSpec.metronome]);
      host
        ..command(MidiHostCommands.load, {
          'timeline': midiTimelineToMap(_clicks()),
        })
        ..command(MidiHostCommands.loop, {'start': 0, 'end': 2})
        ..command(MidiHostCommands.speed, {'value': 2})
        ..command(MidiHostCommands.play);
      expect(_onsets(host.render(2)), [
        for (var i = 0; i < 4; i++) i * _rate ~/ 2 + 1,
      ]);
      expect(host.ofType(MidiHostEvents.position).last['speed'], 2);
      host.command(MidiHostCommands.mix, {
        'tracks': [
          [0, 0],
        ],
      });
      // Faded out over the next block.
      expect(_peak(host.render(1).sublist(128)), 0);
    });

    test('transpose, sync, errors', () {
      var host = _Host([MidiSynthSpec.metronome]);
      host
        ..command(MidiHostCommands.transpose, {'value': 3})
        ..command(MidiHostCommands.sync, {'id': 7})
        ..command('nope')
        ..command(MidiHostCommands.load, {'timeline': 'nope'})
        ..command(MidiHostCommands.play);
      expect(host.host.engine.transpose, 3);
      expect(host.ofType(MidiHostEvents.sync).single['id'], 7);
      expect(host.ofType(MidiHostEvents.error), hasLength(2));
      // Nothing loaded: still stopped.
      expect(host.lastState, isNull);
      expect(_peak(host.render(0.1)), 0);
    });
  });
}
