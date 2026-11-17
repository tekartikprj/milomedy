import 'dart:async';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:test/test.dart';

const _rate = 8000;

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

/// Two clicks a second, looped over its second.
MidiTimeline _clicks() => midiMetronomeTimeline(bpm: 120, beats: 2);

void main() {
  test('the trainer: its speeds, its checks, as a map', () {
    var trainer = MidiSpeedTrainer(from: 0.6, to: 1, step: 0.05);
    expect(
      [for (var i = 0; i < 10; i++) trainer.speedAfter(i)],
      [
        0.6,
        closeTo(0.65, 1e-12),
        closeTo(0.7, 1e-12),
        closeTo(0.75, 1e-12),
        closeTo(0.8, 1e-12),
        closeTo(0.85, 1e-12),
        closeTo(0.9, 1e-12),
        closeTo(0.95, 1e-12),
        1,
        1,
      ],
    );
    var everyTwo = MidiSpeedTrainer(
      from: 1,
      to: 0.5,
      step: 0.2,
      everyPasses: 2,
    );
    expect(
      [for (var i = 0; i < 8; i++) everyTwo.speedAfter(i)],
      [1, 1, 0.8, 0.8, closeTo(0.6, 1e-12), closeTo(0.6, 1e-12), 0.5, 0.5],
    );
    expect(MidiSpeedTrainer.fromMap(everyTwo.toMap()), everyTwo);
    expect('$everyTwo', contains('every 2 passes'));
    expect(
      () => MidiSpeedTrainer(from: 0, to: 1, step: 0.1),
      throwsArgumentError,
    );
    expect(
      () => MidiSpeedTrainer(from: 1, to: -1, step: 0.1),
      throwsArgumentError,
    );
    expect(
      () => MidiSpeedTrainer(from: 1, to: 2, step: 0),
      throwsArgumentError,
    );
    expect(
      () => MidiSpeedTrainer(from: 1, to: 2, step: 0.1, everyPasses: 0),
      throwsArgumentError,
    );
  });

  test('offline: the speed changes at the frame of the loop start', () {
    var engine = midiMetronomeEngine(sampleRate: _rate);
    var timeline = _clicks();
    engine
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..speedTrainer = MidiSpeedTrainer(from: 1, to: 2, step: 0.5);
    expect(engine.speed, 1);
    // Rendered a frame at a time: the speed of each frame.
    var speeds = <double>[];
    var samples = <double>[];
    for (var frame = 0; frame < 3 * _rate; frame++) {
      var block = engine.render(1);
      speeds.add(block.speed);
      samples.add(block.left.first[0]);
    }
    var changes = [
      for (var frame = 1; frame < speeds.length; frame++)
        if (speeds[frame] != speeds[frame - 1]) frame,
    ];
    expect([for (var frame in changes) speeds[frame]], [1.5, 2]);
    // A pass at 1 (8000 frames), then at 1.5 (5333.3 frames, the nearest).
    expect(changes, [_rate, _rate + 5333]);
    // Each change is a loop start: the accented click starts there (a sine:
    // its first sample is 0), the second click of the pass at its speed.
    var onsets = _onsets(samples);
    var loopStarts = [0, ...changes];
    for (var start in loopStarts) {
      expect(onsets, contains(start + 1));
    }
    expect(onsets.sublist(0, 6), [
      1,
      _rate ~/ 2 + 1,
      _rate + 1,
      _rate + 2667 + 1,
      _rate + 5333 + 1,
      _rate + 5333 + 2000 + 1,
    ]);
    expect(engine.loopPasses, greaterThanOrEqualTo(4));
    // The same rendered in blocks of 128 frames, as a worklet does.
    var other = midiMetronomeEngine(sampleRate: _rate)
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..speedTrainer = MidiSpeedTrainer(from: 1, to: 2, step: 0.5);
    var blocks = <double>[];
    for (var i = 0; i < 3 * _rate / 128; i++) {
      blocks.addAll(other.render(128).left.first);
    }
    expect(_onsets(blocks).sublist(0, 6), onsets.sublist(0, 6));
    // midiRenderOffline too.
    var offline = midiMetronomeEngine(sampleRate: _rate)
      ..setLoop(timeline.start, timeline.end)
      ..speedTrainer = MidiSpeedTrainer(from: 1, to: 2, step: 0.5);
    var stereo = midiRenderOffline(offline, timeline, tail: 1.5);
    var left = [for (var i = 0; i < stereo.length; i += 2) stereo[i]];
    expect(_onsets(left).sublist(0, 6), onsets.sublist(0, 6));
  });

  test('setting the speed stops it, no loop no change', () {
    var engine = midiMetronomeEngine(sampleRate: _rate)
      ..load(_clicks())
      ..speedTrainer = MidiSpeedTrainer(from: 0.5, to: 1, step: 0.25);
    expect(engine.speedTrainer, isNotNull);
    engine.render(3 * _rate);
    // No loop: no pass.
    expect(engine.speed, 0.5);
    expect(engine.loopPasses, 0);
    engine.speed = 0.75;
    expect(engine.speedTrainer, isNull);
    engine
      ..setLoop(0, 1)
      ..seek(0)
      ..render(3 * _rate);
    expect(engine.speed, 0.75);
  });

  test('the host reports the speed, the player follows', () async {
    var player = _InProcessPlayer();
    var speeds = <double>[];
    player.onSpeed.listen(speeds.add);
    var timeline = _clicks();
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..setSpeedTrainer(from: 1, to: 2, step: 0.5);
    expect(player.speedTrainer, MidiSpeedTrainer(from: 1, to: 2, step: 0.5));
    expect(player.speed, 1);
    await player.play();
    // A pass at 1, then the next one at 1.5.
    player.render(1.1);
    expect(player.speed, 1.5);
    player.render(1);
    expect(player.speed, 2);
    await Future<void>.delayed(Duration.zero);
    expect(speeds, [1.5, 2]);
    // The speed set by the page wins over the reports sent before.
    player.speed = 0.5;
    expect(player.speedTrainer, isNull);
    player.render(0.2);
    expect(player.speed, 0.5);
    expect(player.host.engine.speedTrainer, isNull);
    player.clearSpeedTrainer();
    expect(player.speedTrainer, isNull);
    await player.close();
  });

  test(
    'MidiPlayer: the trainer in the engine, the speed of each block',
    () async {
      var now = 0.0;
      var sink = MidiSilentSink(
        sampleRate: _rate,
        clock: () => now,
        keep: true,
      );
      var player = MidiPlayer(sink, midiMetronomeEngine(sampleRate: _rate));
      var timeline = _clicks();
      player
        ..load(timeline)
        ..setLoop(timeline.start, timeline.end)
        ..setSpeedTrainer(from: 1, to: 2, step: 0.5);
      expect(player.speedTrainer, isNotNull);
      await player.play();
      for (; now < 2; now += 0.02) {
        player.pump();
      }
      var blockSpeeds = {for (var (_, block) in sink.blocks) block.speed};
      expect(blockSpeeds, {1, 1.5, 2});
      player.clearSpeedTrainer();
      expect(player.speedTrainer, isNull);
      await player.close();
    },
  );
}

/// A player whose host runs here, rendered by hand.
class _InProcessPlayer extends MidiHostPlayer {
  late final MidiEngineHost host;
  var frame = 0;

  _InProcessPlayer() : super(trackCount: 1) {
    host = MidiEngineHost(
      sampleRate: _rate,
      synths: [MidiSynthSpec.metronome],
      send: handleEvent,
    );
  }

  @override
  void sendCommand(Map<String, Object?> command) => host.handle(command);

  @override
  double get clock => frame / _rate;

  /// Renders [seconds] in blocks of 128 frames.
  void render(double seconds) {
    for (var i = 0; i < (seconds * _rate / 128).round(); i++) {
      host.render(Float32List(128), Float32List(128), frame / _rate);
      frame += 128;
    }
  }
}
