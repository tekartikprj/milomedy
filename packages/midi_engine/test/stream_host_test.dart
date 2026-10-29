import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
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

void main() {
  late _FakeStream stream;
  late MidiStreamHost host;
  late List<Map<String, Object?>> events;
  var now = 0.0;

  setUp(() {
    now = 0;
    stream = _FakeStream();
    events = [];
    host = MidiStreamHost(
      stream: stream,
      sampleRate: _rate,
      synths: [MidiSynthSpec.metronome],
      send: events.add,
      blockFrames: 100,
      clock: () => now,
    );
  });

  /// Feeds every 10 ms until [until].
  void run(double until) {
    for (; now < until; now += 0.01) {
      host.feed();
    }
  }

  test('silence ahead of the clock, then the music', () {
    host.feed();
    // 0.1 s ahead, in blocks of 100 frames.
    expect(stream.frames.length, 2 * 800);
    expect(_peak(stream.frames), 0);
    var timeline = midiMetronomeTimeline(bpm: 120, beats: 2);
    host
      ..handle({
        'type': MidiHostCommands.load,
        'timeline': midiTimelineToMap(timeline),
      })
      ..handle({'type': MidiHostCommands.loop, 'start': 0, 'end': 1})
      ..handle({'type': MidiHostCommands.play});
    run(2);
    // Played from the first block pushed after the command (800), a click
    // every half second (a sine: its first sample is 0).
    expect(_onsets(stream.left), [
      for (var i = 0; i < 4; i++) 800 + i * _rate ~/ 2 + 1,
    ]);
    // Kept 0.1 s ahead.
    expect(host.ahead, closeTo(0.1, 0.0125));
  });

  test('the position heard, a full stream, ran out', () {
    host
      ..handle({
        'type': MidiHostCommands.load,
        'timeline': midiTimelineToMap(midiMetronomeTimeline(bpm: 60)),
      })
      ..handle({'type': MidiHostCommands.play});
    run(1);
    // Rendered 0.1 s ahead, heard now.
    var report = events
        .where((event) => event['type'] == MidiHostEvents.position)
        .last;
    expect(report.containsKey('time'), isFalse);
    expect(report['position']! as double, lessThan(now));
    expect(report['position']! as double, greaterThan(now - 0.7));
    // Full: the block is kept, pushed once there is room.
    var pushed = stream.frames.length;
    stream.full = true;
    run(1.2);
    expect(stream.frames.length, pushed);
    stream.full = false;
    run(1.3);
    // Full while the clock went on: the stream is behind its clock, what is
    // pushed now plays now (0.1 s skipped).
    expect(stream.frames.length, closeTo(2 * 1.3 * _rate, 2 * 100));
    // Ran out: the stream played everything, its clock moves on.
    var before = host.currentTime;
    stream.exhausted++;
    host.feed();
    expect(host.currentTime, greaterThan(before));
  });
}
