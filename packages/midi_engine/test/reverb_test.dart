import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 8000;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// A click at [start] (the start by default) of 2 s, on track 0.
MidiTimeline _click({double start = 0}) => MidiTimeline(
  notes: [
    MidiTimelineNote(
      start: start,
      duration: 0.05,
      key: midiKeyHiWoodBlock,
      channel: midiPercussionChannel,
    ),
  ],
  end: 2,
);

/// A block of [frames] frames: [value] on track 0, from frame 0 to [until].
MidiRenderBlock _block(int frames, double value, {int until = 1}) {
  Float32List track() => Float32List(frames)..fillRange(0, until, value);
  return MidiRenderBlock([track()], [track()], frames, 0);
}

void main() {
  group('reverb', () {
    test('an impulse: a tail from the first comb, decaying', () {
      var reverb = MidiReverb(sampleRate: 44100);
      var input = Float32List(44100 * 3)..[0] = 1;
      var left = Float32List(input.length);
      var right = Float32List(input.length);
      reverb.process(input, left, right, input.length);
      // Nothing before the shortest comb (1116 frames at 44.1 kHz).
      expect(_peak(left.sublist(0, 1116)), 0);
      expect(_peak(left.sublist(1116, 1116 + 2000)), greaterThan(0.01));
      // The two sides differ (the stereo spread).
      expect(right.sublist(1116, 1200), isNot(left.sublist(1116, 1200)));
      // Decaying: under 1/1000 of its start after 2 s.
      expect(
        _peak(left.sublist(2 * 44100)),
        lessThan(_peak(left.sublist(0, 4410)) / 1000),
      );
      // The same each time.
      var again = Float32List(left.length);
      MidiReverb(
        sampleRate: 44100,
      ).process(input, again, Float32List(left.length), input.length);
      expect(again, left);
      // Muted: no tail left.
      reverb.mute();
      reverb.process(Float32List(4410), left, right, 4410);
      expect(_peak(left.sublist(0, 4410)), 0);
    });

    test('settings', () {
      var reverb = MidiReverb(sampleRate: 8000, roomSize: 0.2, damp: 0.7)
        ..width = 0.5
        ..wet = 0.5;
      expect(reverb.roomSize, closeTo(0.2, 1e-9));
      expect(reverb.damp, closeTo(0.7, 1e-9));
      expect(reverb.width, 0.5);
      expect(reverb.wet, closeTo(0.5, 1e-9));
      // A smaller room: a shorter tail.
      double tail(MidiReverb reverb) {
        var input = Float32List(8000 * 2)..[0] = 1;
        var left = Float32List(input.length);
        reverb.process(input, left, Float32List(input.length), input.length);
        return _peak(left.sublist(8000));
      }

      expect(
        tail(MidiReverb(sampleRate: 8000, roomSize: 0.2)),
        lessThan(tail(MidiReverb(sampleRate: 8000)) / 10),
      );
    });

    test('the bus: idle until sent to, idle again after its tail', () {
      var bus = MidiReverbBus(sampleRate: _rate);
      expect(bus.idle, isTrue);
      expect(bus.process(128, fed: false), isFalse);
      // Silence sent: still idle.
      bus.input(128);
      expect(bus.process(128, fed: true), isFalse);
      bus.input(128)[0] = 1;
      expect(bus.process(128, fed: true), isTrue);
      expect(bus.idle, isFalse);
      var blocks = 0;
      while (bus.process(128, fed: false)) {
        blocks++;
      }
      // A tail of about a second at this level, then idle.
      expect(blocks * 128 / _rate, inInclusiveRange(0.5, 4));
      expect(bus.idle, isTrue);
    });
  });

  group('mixdown', () {
    test('no send: as before, no reverb', () {
      var block = _block(256, 0.5, until: 10);
      var mixdown = MidiStereoMixdown(sampleRate: _rate)
        ..setTrack(0, gain: 0.8, pan: 0.3);
      var left = Float32List(256);
      var right = Float32List(256);
      mixdown.mix(block, left, right);
      var mixer = MidiMixer(1)
        ..tracks[0].volume = 0.8
        ..tracks[0].pan = 0.3;
      var expected = midiMixStereo(block, mixer, masterGain: midiMasterGain);
      MidiLimiter(sampleRate: _rate).process(expected);
      for (var i = 0; i < 256; i++) {
        expect(left[i], expected[2 * i]);
        expect(right[i], expected[2 * i + 1]);
      }
      expect(mixdown.reverbIdle, isTrue);
    });

    test('a send: a tail, at the level of the reverb; muted, none', () {
      List<double> render({
        double send = 0.5,
        double gain = 1,
        double level = 1,
      }) {
        var mixdown = MidiStereoMixdown(sampleRate: _rate)
          ..setTrack(0, gain: gain, pan: 0, reverb: send)
          ..reverbLevel = level;
        expect(mixdown.reverbLevel, level);
        var samples = <double>[];
        for (var i = 0; i < 40; i++) {
          var left = Float32List(128);
          mixdown.mix(
            i == 0 ? _block(128, 0.5, until: 64) : _block(128, 0),
            left,
            Float32List(128),
          );
          samples.addAll(left);
        }
        return samples;
      }

      var wet = render();
      // The click, then its tail.
      expect(_peak(wet.sublist(0, 64)), greaterThan(0.4));
      var tail = _peak(wet.sublist(640));
      expect(tail, greaterThan(0.002));
      expect(_peak(render(send: 0).sublist(640)), 0);
      expect(_peak(render(gain: 0).sublist(640)), 0);
      expect(_peak(render(level: 0).sublist(640)), 0);
      // Twice the send, twice the tail (under the limit).
      expect(_peak(render(send: 1).sublist(640)), closeTo(2 * tail, 1e-4));
    });

    test('peaks per track, after the gain', () {
      var mixdown = MidiStereoMixdown(sampleRate: _rate)
        ..setTrack(0, gain: 0.5, pan: 0)
        ..setTrack(1, gain: 0, pan: 0);
      var block = MidiRenderBlock(
        [Float32List(64)..[3] = -0.8, Float32List(64)..fillRange(0, 64, 1)],
        [Float32List(64), Float32List(64)],
        64,
        0,
      );
      mixdown.mix(block, Float32List(64), Float32List(64));
      expect(mixdown.takePeaks(3), [closeTo(0.4, 1e-6), 0, 0]);
      // Taken: from 0 again.
      expect(mixdown.takePeaks(2), [0, 0]);
    });
  });

  group('host', () {
    test('a send: the tail heard, the end waits for it', () {
      List<double> play(List<Object> mix, {Object? reverb}) {
        var events = <Map<String, Object?>>[];
        var host = MidiEngineHost(
          sampleRate: _rate,
          synths: [MidiSynthSpec.metronome],
          send: events.add,
        );
        host
          ..handle({
            'type': MidiHostCommands.load,
            'timeline': midiTimelineToMap(_click(start: 1.9)),
          })
          ..handle({
            'type': MidiHostCommands.mix,
            'tracks': [mix],
            'reverb': ?reverb,
          })
          ..handle({'type': MidiHostCommands.play});
        var samples = <double>[];
        // 4 s, the timeline is 2 s.
        for (var i = 0; i < 4 * _rate / 128; i++) {
          var left = Float32List(128);
          host.render(left, Float32List(128), i * 128 / _rate);
          samples.addAll(left);
          if (host.state == MidiPlayerState.stopped) {
            break;
          }
        }
        return samples;
      }

      // The old format, [gain, pan]: dry, stops at the end of the song.
      var click = (1.9 * _rate).round();
      var dry = play([1, 0]);
      expect(_peak(dry.sublist(click + _rate ~/ 10)), 0);
      expect(dry.length / _rate, closeTo(2, 0.05));
      var wet = play([1, 0, 1]);
      expect(
        _peak(wet.sublist(click + _rate ~/ 10, click + _rate ~/ 2)),
        greaterThan(0.001),
      );
      // The tail rings past the end of the song, then it stops.
      expect(wet.length, greaterThan(dry.length));
      expect(wet.length / _rate, lessThan(4));
      // The level of the reverb: 0, no tail.
      var muted = play([1, 0, 1], reverb: 0);
      expect(_peak(muted.sublist(click + _rate ~/ 10)), 0);
    });

    test('a pause cuts the tail, none when playing again', () {
      var host = MidiEngineHost(
        sampleRate: _rate,
        synths: [MidiSynthSpec.metronome],
        send: (_) {},
      );
      host
        ..handle({
          'type': MidiHostCommands.load,
          'timeline': midiTimelineToMap(_click()),
        })
        ..handle({
          'type': MidiHostCommands.mix,
          'tracks': [
            [1, 0, 1],
          ],
        })
        ..handle({'type': MidiHostCommands.play});
      List<double> render(double seconds) {
        var samples = <double>[];
        for (var i = 0; i < seconds * _rate / 128; i++) {
          var left = Float32List(128);
          host.render(left, Float32List(128), 0);
          samples.addAll(left);
        }
        return samples;
      }

      render(0.2);
      host.handle({'type': MidiHostCommands.pause});
      render(0.1);
      expect(host.state, MidiPlayerState.paused);
      host.handle({'type': MidiHostCommands.play});
      // After the click (at 0, already played): silence, no old tail.
      expect(_peak(render(0.5)), 0);
    });
  });

  group('players', () {
    test('MidiPlayer on a stream: the tail of a send', () async {
      Future<List<double>> play(double send) async {
        var now = 0.0;
        var stream = _FakeStream();
        var sink = MidiStreamSink(stream, sampleRate: _rate, clock: () => now);
        var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: _rate))
          ..load(_click())
          ..setReverb(0, send);
        expect(player.reverbLevel, 1);
        player.reverbLevel = 0.5;
        expect(player.mixer.reverbLevel, 0.5);
        await player.play();
        for (; now < 1; now += 0.01) {
          player.pump();
          sink.feed();
        }
        await player.close();
        return stream.left;
      }

      var dry = await play(0);
      var wet = await play(1);
      var start = dry.indexWhere((sample) => sample != 0);
      expect(start, greaterThanOrEqualTo(0));
      var after = start + _rate ~/ 10;
      expect(_peak(dry.sublist(after)), 0);
      expect(_peak(wet.sublist(after)), greaterThan(0.0005));
    });

    test('MidiPlayer sends the reverb to a sink that mixes it', () {
      var sink = MidiSilentSink(sampleRate: _rate);
      var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: _rate))
        ..setReverb(0, 0.3)
        ..reverbLevel = 0.7;
      expect(sink.reverbs, {0: 0.3});
      expect(sink.reverbLevel, 0.7);
      expect(player.mixer.reverbOf(0), 0.3);
    });

    test('offline: the sends of the mixer', () {
      var dry = midiRenderOffline(
        midiMetronomeEngine(sampleRate: _rate),
        _click(),
      );
      var mixer = MidiMixer(1)..tracks[0].reverb = 1;
      var wet = midiRenderOffline(
        midiMetronomeEngine(sampleRate: _rate),
        _click(),
        mixer: mixer,
      );
      expect(wet.length, dry.length);
      // The same dry part (the reverb starts after its first comb).
      expect(wet.sublist(0, 200), dry.sublist(0, 200));
      expect(_peak(dry.sublist(2 * _rate ~/ 10)), 0);
      expect(_peak(wet.sublist(2 * _rate ~/ 10)), greaterThan(0.001));
    });
  });

  test('the sends of the CC 91 of a timeline', () {
    MidiTimelineMessage reverb(double time, int track, int value) =>
        MidiTimelineMessage(
          time: time,
          track: track,
          status: midiControlChange,
          data1: midiControllerReverb,
          data2: value,
        );
    var timeline = MidiTimeline(
      notes: [
        for (var track = 0; track < 4; track++)
          MidiTimelineNote(start: 1, duration: 1, key: 60, track: track),
      ],
      messages: [
        // Track 0: 20 then 100 at its first note, 0 after.
        reverb(0, 0, 20),
        reverb(1, 0, 100),
        reverb(1.5, 0, 0),
        // Track 1: set after its first note only.
        reverb(1.5, 1, 64),
        // Track 4: no notes.
        reverb(0, 4, 127),
        // Not a reverb.
        const MidiTimelineMessage(
          time: 0,
          track: 2,
          status: midiControlChange,
          data1: midiControllerVolume,
          data2: 10,
        ),
      ],
    );
    expect(midiReverbSends(timeline, trackCount: 5), [
      100 / 127,
      64 / 127,
      midiDefaultReverbSend,
      midiDefaultReverbSend,
      0,
    ]);
    expect(midiReverbSends(timeline, trackCount: 3, missing: 0), [
      100 / 127,
      64 / 127,
      0,
    ]);
  });
}

/// A raw stream keeping what is pushed, interleaved stereo.
class _FakeStream implements MidiPcmStream {
  final frames = <double>[];

  @override
  bool push(Float32List chunk) {
    frames.addAll(chunk);
    return true;
  }

  @override
  int get exhaustCount => 0;

  @override
  void close() {}

  /// The left channel.
  List<double> get left => [
    for (var i = 0; i < frames.length; i += 2) frames[i],
  ];
}
