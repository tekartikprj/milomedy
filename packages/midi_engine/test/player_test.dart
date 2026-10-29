import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
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

/// A raw stream keeping what is pushed, interleaved stereo.
class _FakeStream implements MidiPcmStream {
  final frames = <double>[];
  var exhausted = 0;
  var full = false;
  var closed = false;

  @override
  bool push(Float32List chunk) {
    if (full) {
      return false;
    }
    frames.addAll(chunk);
    return true;
  }

  @override
  int get exhaustCount => exhausted;

  @override
  void close() => closed = true;

  /// The left channel.
  List<double> get left => [
    for (var i = 0; i < frames.length; i += 2) frames[i],
  ];
}

/// A block of [frames] frames, [value] on track 0 (left and right).
MidiRenderBlock _block(int frames, double value) => MidiRenderBlock(
  [Float32List(frames)..fillRange(0, frames, value), Float32List(frames)],
  [Float32List(frames)..fillRange(0, frames, value), Float32List(frames)],
  frames,
  0,
);

MidiEngine _engine() => MidiEngine(
  sampleRate: _rate,
  synths: [DartSynth(sampleRate: _rate, instrument: ReedInstrument.treble())],
);

/// Quarter notes at [bpm] on track 0.
MidiTimeline _notes(List<int> keys, {double bpm = 60}) => MidiTimeline(
  notes: [
    for (var (i, key) in keys.indexed)
      MidiTimelineNote(start: i * 60 / bpm, duration: 50 / bpm, key: key),
  ],
);

void main() {
  group('player', () {
    test('feeds the output ahead of its clock, tells the position', () async {
      var now = 0.0;
      var sink = MidiSilentSink(
        sampleRate: _rate,
        clock: () => now,
        keep: true,
      );
      var player = MidiPlayer(sink, _engine());
      expect(sink.mixes, {0: (1.0, 0.0)});
      player.load(_notes([60, 62, 64, 65]));
      expect(player.state, MidiPlayerState.stopped);
      await player.play();
      expect(player.isPlaying, isTrue);
      expect(sink.blocks, isNotEmpty);
      var scheduled = sink.blocks.last.$1;
      expect(scheduled, lessThan(0.04 + player.lookahead + 0.3));
      for (; now < 1; now += 0.02) {
        player.pump();
      }
      expect(player.position, closeTo(0.96, 0.03));
      player.pause();
      expect(player.state, MidiPlayerState.paused);
      expect(sink.blocks, isEmpty);
      expect(player.position, closeTo(0.96, 0.03));
      // Past the end: stopped.
      await player.play();
      for (var t = 1.0; t < 8; t += 0.1) {
        now = t;
        player.pump();
      }
      expect(player.state, MidiPlayerState.stopped);
      await player.close();
    });

    test('the position at another speed, a block never crosses the loop '
        'end', () async {
      var now = 0.0;
      var sink = MidiSilentSink(
        sampleRate: _rate,
        clock: () => now,
        keep: true,
      );
      var player = MidiPlayer(sink, _engine())
        ..load(_notes([60, 62, 64, 65, 67, 69, 71, 72]));
      player.speed = 2;
      await player.play();
      for (; now < 1; now += 0.02) {
        player.pump();
      }
      expect(player.position, closeTo(1.92, 0.06));
      player.setLoop(2, 3);
      for (; now < 3; now += 0.02) {
        player.pump();
      }
      for (var (_, block) in sink.blocks) {
        var end = block.songStart + block.frames * block.speed / _rate;
        expect(
          block.songStart >= 3 - 1e-9 || end <= 3 + 1e-9,
          isTrue,
          reason: '${block.songStart} $end',
        );
      }
      expect(player.position, inInclusiveRange(2, 3));
      await player.close();
    });

    test('the mix', () async {
      var sink = MidiSilentSink(sampleRate: _rate);
      var engine = MidiEngine(
        sampleRate: _rate,
        synths: [
          DartSynth(sampleRate: _rate),
          DartSynth(sampleRate: _rate),
        ],
      );
      var player = MidiPlayer(sink, engine)
        ..setVolume(0, 0.5)
        ..setPan(1, -1);
      expect(sink.mixes, {0: (0.5, 0.0), 1: (1.0, -1.0)});
      player.setSolo(1, true);
      expect(sink.mixes[0], (0.0, 0.0));
      player
        ..setSolo(1, false)
        ..setMute(0, true);
      expect(sink.mixes, {0: (0.0, 0.0), 1: (1.0, -1.0)});
      expect(
        () => MidiPlayer(MidiSilentSink(sampleRate: 44100), engine),
        throwsArgumentError,
      );
      await player.close();
    });
  });

  group('stream', () {
    test('blocks at their frame, ahead of the clock', () async {
      var now = 0.0;
      var stream = _FakeStream();
      var sink = MidiStreamSink(
        stream,
        sampleRate: _rate,
        latency: 0.1,
        chunkFrames: 100,
        clock: () => now,
      );
      await sink.resume();
      sink.setTrackMix(0, gain: 0.8, pan: 0);
      // A block at 0.05 s: 400 frames of silence first.
      sink.schedule(0.05, _block(200, 0.5));
      sink.schedule(0.05 + 200 / _rate, _block(200, 0.25));
      // Fed once the blocks are scheduled.
      expect(stream.frames, isEmpty);
      await Future<void>.value();
      expect(stream.frames.length, 2 * 800);
      var left = stream.left;
      expect(_onset(left), 400);
      // The volume, the master gain.
      var expected = 0.5 * 0.8 * midiMasterGain;
      expect(left[450], closeTo(expected, 1e-6));
      expect(left[650], closeTo(expected / 2, 1e-6));
      // Nothing more until the clock moves on.
      sink.feed();
      expect(stream.frames.length, 2 * 800);
      now = 0.05;
      sink.feed();
      expect(stream.frames.length, 2 * 1200);
      // Cancelled: silence from what is pushed next.
      sink.cancel();
      now = 0.1;
      sink.feed();
      expect(_peak(stream.left.sublist(1200)), 0);
      // A block must start after what the stream holds.
      expect(sink.startLatency, closeTo(0.1 + 0.01, 1e-3));
      await sink.close();
      expect(stream.closed, isTrue);
    });

    test('gains, pans, limiter, a full stream, late', () async {
      var now = 0.0;
      var stream = _FakeStream();
      var sink = MidiStreamSink(
        stream,
        sampleRate: _rate,
        latency: 0.1,
        chunkFrames: 100,
        clock: () => now,
      );
      await sink.resume();
      sink.setTrackMix(0, gain: 1, pan: 1);
      sink.setTrackMix(0, gain: 0, pan: 1);
      sink.schedule(0, _block(4000, 1));
      sink.feed();
      // The gain moves to 0 over the first chunk, then silence; all on the
      // right.
      expect(stream.frames[1], greaterThan(0));
      expect(_peak(stream.left), lessThan(1e-9));
      expect(_peak(stream.frames.sublist(200)), 0);
      sink.setTrackMix(0, gain: 1, pan: 0);
      now = 0.1;
      sink.feed();
      // Loud: kept under the limit.
      expect(_peak(stream.frames), lessThanOrEqualTo(midiLimit + 1e-6));
      expect(_peak(stream.left.sublist(900)), greaterThan(0.4));
      // Full: nothing pushed, nothing lost from the queue.
      stream.full = true;
      now = 0.2;
      sink.feed();
      expect(stream.frames.length, 2 * 1600);
      stream.full = false;
      // Late (the stream ran out): what is pushed now plays now.
      now = 0.4;
      sink.feed();
      expect(stream.frames.length, 2 * (1600 + 800));
      await sink.close();
    });

    test('ran out early, the clock moves on', () async {
      var now = 0.0;
      var stream = _FakeStream();
      var sink = MidiStreamSink(
        stream,
        sampleRate: _rate,
        latency: 0.1,
        chunkFrames: 100,
        clock: () => now,
      );
      await sink.resume();
      sink.schedule(0, _block(4000, 0.1));
      sink.feed();
      expect(sink.currentTime, 0);
      // The stream played everything pushed (its clock is faster).
      stream.exhausted++;
      sink.feed();
      expect(sink.currentTime, closeTo(0.1, 1e-9));
      // Counted while it waited for the first frames: the clock stays.
      var waiting = _FakeStream()..exhausted = 3;
      var fresh = MidiStreamSink(
        waiting,
        sampleRate: _rate,
        chunkFrames: 100,
        clock: () => now,
      );
      await fresh.resume();
      fresh.schedule(0, _block(4000, 0.1));
      waiting.exhausted++;
      fresh.feed();
      fresh.feed();
      expect(fresh.currentTime, 0);
      await fresh.close();
      await sink.close();
    });

    test('player on a stream', () async {
      var now = 0.0;
      var stream = _FakeStream();
      var sink = MidiStreamSink(stream, sampleRate: _rate, clock: () => now);
      var player = MidiPlayer(sink, _engine());
      player.load(_notes([72, 74, 76, 77], bpm: 120));
      await player.play();
      for (; now < 3; now += 0.01) {
        player.pump();
        sink.feed();
      }
      expect(player.state, MidiPlayerState.stopped);
      // The notes, then the release, then silence.
      var left = stream.left;
      expect(_peak(left), greaterThan(0.05));
      expect(_peak(left), lessThanOrEqualTo(midiLimit + 1e-6));
      expect(_onset(left), lessThan((0.1 * _rate).round()));
      await player.close();
    });
  });
}
