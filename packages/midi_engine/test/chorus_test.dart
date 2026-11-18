import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 8000;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// The index of the largest sample of [samples].
int _argMax(List<double> samples) {
  var best = 0;
  for (var i = 1; i < samples.length; i++) {
    if (samples[i].abs() > samples[best].abs()) {
      best = i;
    }
  }
  return best;
}

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
  group('chorus', () {
    test('an impulse: delayed by the sweep, the right a quarter later', () {
      var chorus = MidiChorus(sampleRate: _rate);
      var inputLeft = Float32List(64)..[0] = 1;
      var inputRight = Float32List(64)..[0] = 1;
      var left = Float32List(64);
      var right = Float32List(64);
      chorus.process(inputLeft, inputRight, left, right, 64);
      // Left: 2 ms (the sweep at its middle, already moving), 16 frames at
      // 8 kHz: shared by the frames 16 and 17.
      expect(_argMax(left), 16);
      expect(left[16] + left[17], closeTo(1, 0.01));
      // Right: a quarter of a period later, 2 + 1.9 ms, 31.2 frames:
      // between 31 and 32.
      expect(_argMax(right), 31);
      expect(right[31] + right[32], closeTo(1, 0.01));
      // Wet only: nothing at once.
      expect(left[0], 0);
      expect(right[0], 0);
      chorus.mute();
      chorus.process(Float32List(64), Float32List(64), left, right, 64);
      expect(_peak(left), 0);
      expect(_peak(right), 0);
    });

    test('the bus: idle until sent to, idle again once empty', () {
      var bus = MidiChorusBus(sampleRate: _rate);
      expect(bus.idle, isTrue);
      expect(bus.process(64, fed: false), isFalse);
      var (inputLeft, _) = bus.input(64);
      inputLeft[0] = 1;
      expect(bus.process(64, fed: true), isTrue);
      expect(bus.idle, isFalse);
      expect(_peak(bus.left), greaterThan(0.9));
      // Nothing more: its delay line empties within 4 ms.
      expect(bus.process(64, fed: false), isTrue);
      expect(bus.idle, isTrue);
      expect(bus.process(64, fed: false), isFalse);
    });
  });

  group('mixdown', () {
    List<double> render({
      double send = 0.5,
      double gain = 1,
      double level = 1,
      double pan = 0,
      bool right = false,
    }) {
      var mixdown = MidiStereoMixdown(sampleRate: _rate)
        ..setTrack(0, gain: gain, pan: pan, chorus: send)
        ..chorusLevel = level;
      expect(mixdown.chorusLevel, level);
      var samples = <double>[];
      for (var i = 0; i < 4; i++) {
        var outLeft = Float32List(128);
        var outRight = Float32List(128);
        mixdown.mix(
          i == 0 ? _block(128, 0.5) : _block(128, 0),
          outLeft,
          outRight,
        );
        samples.addAll(right ? outRight : outLeft);
      }
      expect(mixdown.effectsIdle, isTrue);
      return samples;
    }

    test('a send: the delayed copy, at the level of the chorus', () {
      var dry = render(send: 0);
      // The click alone, dry.
      expect(_peak(dry.sublist(1)), 0);
      var wet = render();
      expect(wet[0], dry[0]);
      // Its copy 2 ms later (frames 16 and 17), times the send.
      double copy(List<double> samples) => samples[16] + samples[17];
      expect(copy(wet), closeTo(dry[0] * 0.5, 0.01));
      expect(_peak(render(gain: 0)), 0);
      expect(_peak(render(level: 0).sublist(1)), 0);
      expect(copy(render(level: 0.5)), closeTo(dry[0] * 0.25, 0.01));
    });

    test('the chorus follows the pan of the track', () {
      // Hard left: nothing on the right, wet or dry.
      expect(_peak(render(pan: -1, right: true)), 0);
      expect(_peak(render(pan: -1).sublist(1)), greaterThan(0.1));
    });
  });

  group('host', () {
    test('a send: the copy heard, [gain, pan, reverb, chorus]', () {
      List<double> play(List<Object> mix, {Object? chorus}) {
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
            'tracks': [mix],
            'chorus': ?chorus,
          })
          ..handle({'type': MidiHostCommands.play});
        var samples = <double>[];
        for (var i = 0; i < 2.5 * _rate / 128; i++) {
          var left = Float32List(128);
          host.render(left, Float32List(128), i * 128 / _rate);
          samples.addAll(left);
          if (host.state == MidiPlayerState.stopped) {
            break;
          }
        }
        return samples;
      }

      var dry = play([1, 0, 0]);
      var wet = play([1, 0, 0, 1]);
      expect(wet.length, dry.length);
      var differs = false;
      for (var i = 0; i < dry.length && !differs; i++) {
        differs = wet[i] != dry[i];
      }
      expect(differs, isTrue);
      expect(play([1, 0, 0, 1], chorus: 0), dry);
    });
  });

  group('players', () {
    test('MidiPlayer sends the chorus to a sink that mixes it', () {
      var sink = MidiSilentSink(sampleRate: _rate);
      var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: _rate))
        ..setChorus(0, 0.3)
        ..chorusLevel = 0.7;
      expect(sink.choruses, {0: 0.3});
      expect(sink.chorusLevel, 0.7);
      expect(player.mixer.chorusOf(0), 0.3);
      expect(player.chorusLevel, 0.7);
    });

    test('MidiPlayer on a stream: the copy of a send', () async {
      Future<List<double>> play(double send) async {
        var now = 0.0;
        var stream = _FakeStream();
        var sink = MidiStreamSink(stream, sampleRate: _rate, clock: () => now);
        var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: _rate))
          ..load(_click())
          ..setChorus(0, send);
        await player.play();
        for (; now < 0.5; now += 0.01) {
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
      var differs = false;
      for (var i = start; i < dry.length && !differs; i++) {
        differs = wet[i] != dry[i];
      }
      expect(differs, isTrue);
    });

    test('offline: the sends of the mixer', () {
      var dry = midiRenderOffline(
        midiMetronomeEngine(sampleRate: _rate),
        _click(),
      );
      var mixer = MidiMixer(1)..tracks[0].chorus = 1;
      expect(mixer.hasChorus, isTrue);
      expect(mixer.hasEffects, isTrue);
      var wet = midiRenderOffline(
        midiMetronomeEngine(sampleRate: _rate),
        _click(),
        mixer: mixer,
      );
      expect(wet.length, dry.length);
      // The same start (the copy comes 2 ms later), then different.
      expect(wet.sublist(0, 2 * 16), dry.sublist(0, 2 * 16));
      expect(wet, isNot(dry));
    });
  });

  test('the sends of the CC 93 of a timeline', () {
    MidiTimelineMessage chorus(double time, int track, int value) =>
        MidiTimelineMessage(
          time: time,
          track: track,
          status: midiControlChange,
          data1: midiControllerChorus,
          data2: value,
        );
    var timeline = MidiTimeline(
      notes: [
        for (var track = 0; track < 3; track++)
          MidiTimelineNote(start: 1, duration: 1, key: 60, track: track),
      ],
      messages: [
        chorus(0, 0, 20),
        chorus(1, 0, 100),
        chorus(1.5, 1, 64),
        // A reverb is not a chorus.
        const MidiTimelineMessage(
          time: 0,
          track: 2,
          status: midiControlChange,
          data1: midiControllerReverb,
          data2: 90,
        ),
      ],
    );
    expect(midiChorusSends(timeline, trackCount: 4), [
      100 / 127,
      64 / 127,
      midiDefaultChorusSend,
      0,
    ]);
    expect(midiDefaultChorusSend, 0);
  });
}

/// A stream keeping the left samples pushed (interleaved stereo).
class _FakeStream implements MidiPcmStream {
  final left = <double>[];

  @override
  int exhaustCount = 0;

  @override
  bool push(Float32List frames) {
    for (var i = 0; i < frames.length; i += 2) {
      left.add(frames[i]);
    }
    return true;
  }

  @override
  void close() {}
}
