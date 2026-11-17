import 'dart:async';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:test/test.dart';

const _rate = 44100;

/// Two tracks: a chord of 2 s on track 0 (keys 60 and 64), a note from
/// 0.5 s to 1 s on track 1 (key 67).
MidiTimeline _song() => MidiTimeline(
  notes: const [
    MidiTimelineNote(start: 0, duration: 2, key: 60),
    MidiTimelineNote(start: 0, duration: 2, key: 64),
    MidiTimelineNote(start: 0.5, duration: 0.5, key: 67, track: 1),
  ],
);

const _reeds = [
  MidiSynthSpec(instrument: MidiInstrumentIds.reed),
  MidiSynthSpec(instrument: MidiInstrumentIds.reed),
];

/// A player whose host runs here, rendered by hand.
class _InProcessPlayer extends MidiHostPlayer {
  late final MidiEngineHost host;
  var frame = 0;

  _InProcessPlayer(List<MidiSynthSpec> synths)
    : super(trackCount: synths.length) {
    host = MidiEngineHost(sampleRate: _rate, synths: synths, send: handleEvent);
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

void main() {
  test('the meters event fields and back', () {
    var fields = midiMetersEventFields(Float32List.fromList([0.5, 0, 0.25]), [
      (track: 0, channel: 0, key: 60),
      (track: 2, channel: 9, key: 36),
      (track: 0, channel: 1, key: 60),
    ]);
    expect(fields['levels'], isA<Float32List>());
    expect(fields['keys'], isA<Int32List>());
    expect(fields['keys'], [60, 2 * 128 + 36, 60]);
    // As a list from JS, of two tracks only.
    var meters = MidiTrackMeters.fromEvent({
      'levels': [0.5, 0, 0.25],
      'keys': [60, 2 * 128 + 36, 128 + 61],
    }, 2)!;
    expect(meters.trackCount, 2);
    expect(meters.levels, [0.5, 0]);
    expect(meters.keys, [
      {60},
      {61},
    ]);
    expect(meters.isSilent, isFalse);
    expect(MidiTrackMeters.fromEvent({'position': 1}, 2), isNull);
    expect(MidiTrackMeters.silent(3).isSilent, isTrue);
    expect(MidiTrackMeters.silent(3).keys, hasLength(3));
  });

  test('the host reports them with its position, about 30 a second', () {
    var events = <Map<String, Object?>>[];
    var host = MidiEngineHost(
      sampleRate: _rate,
      synths: _reeds,
      send: events.add,
    );
    expect(host.reportFrames, 1470);
    host
      ..handle({
        'type': MidiHostCommands.load,
        'timeline': midiTimelineToMap(_song()),
      })
      // Track 1 at half its volume.
      ..handle({
        'type': MidiHostCommands.mix,
        'tracks': [
          [1, 0],
          [0.5, 0],
        ],
      })
      ..handle({'type': MidiHostCommands.transpose, 'value': 2})
      ..handle({'type': MidiHostCommands.play});
    // 2 s.
    for (var i = 0; i < 2 * _rate / 128; i++) {
      host.render(Float32List(128), Float32List(128), i * 128 / _rate);
    }
    var reports = events
        .where((event) => event['type'] == MidiHostEvents.position)
        .toList();
    // One every 12 blocks of 128 frames: 28.7 a second, not more than 30.
    expect(reports.length / 2, inInclusiveRange(28, 30));
    for (var report in reports) {
      expect(report['levels'], isA<Float32List>());
      expect(report['keys'], isA<Int32List>());
    }
    MidiTrackMeters at(double position) => MidiTrackMeters.fromEvent(
      reports.firstWhere(
        (report) => (report['position']! as double) >= position,
      ),
      2,
    )!;
    // The first one: nothing rendered yet.
    expect(MidiTrackMeters.fromEvent(reports.first, 2)!.levels, [0, 0]);
    // The chord, transposed.
    var chord = at(0.25);
    expect(chord.keys, [
      {62, 66},
      <int>{},
    ]);
    expect(chord.levels[0], greaterThan(0.1));
    expect(chord.levels[1], 0);
    var both = at(0.75);
    expect(both.keys[1], {69});
    var single = both.levels[1];
    expect(single, greaterThan(0.05));
    // Track 1 alone is about half track 0 (a note, half the volume, against
    // two notes at full volume): after its volume.
    expect(single, lessThan(both.levels[0]));
    expect(at(1.5).keys[1], isEmpty);
  });

  test(
    'the player: trackLevels, soundingKeys, onMeters, silent once paused',
    () async {
      var player = _InProcessPlayer(_reeds);
      var meters = <MidiTrackMeters>[];
      player.onMeters.listen(meters.add);
      expect(player.trackLevels, [0, 0]);
      expect(player.soundingKeys, [<int>{}, <int>{}]);
      player.load(_song());
      await player.play();
      player.render(0.75);
      expect(player.soundingKeys, [
        {60, 64},
        {67},
      ]);
      expect(player.trackLevels[0], greaterThan(0.1));
      expect(player.meters.levels, player.trackLevels);
      await Future<void>.delayed(Duration.zero);
      expect(meters.length, inInclusiveRange(20, 23));
      // Muted: its level is 0, its keys still sound.
      player.setMute(1, true);
      player.render(0.1);
      expect(player.trackLevels[1], 0);
      expect(player.soundingKeys[1], {67});
      player.pause();
      expect(player.meters.isSilent, isTrue);
      player.render(0.1);
      await Future<void>.delayed(Duration.zero);
      expect(meters.last.isSilent, isTrue);
      expect(player.soundingKeys, [<int>{}, <int>{}]);
      await player.close();
    },
  );

  test('the isolate host sends the reports once heard', () {
    var now = 0.0;
    var events = <Map<String, Object?>>[];
    var stream = _NullStream();
    var host = MidiStreamHost(
      stream: stream,
      sampleRate: _rate,
      synths: [const MidiSynthSpec(instrument: MidiInstrumentIds.reed)],
      send: events.add,
      clock: () => now,
    );
    host
      ..handle({
        'type': MidiHostCommands.load,
        'timeline': midiTimelineToMap(
          MidiTimeline(
            notes: const [MidiTimelineNote(start: 0, duration: 4, key: 60)],
          ),
        ),
      })
      ..handle({'type': MidiHostCommands.play});
    for (; now < 1; now += 0.005) {
      var before = events.length;
      host.feed();
      for (var report
          in events
              .skip(before)
              .where((event) => event['type'] == MidiHostEvents.position)) {
        // Rendered 0.1 s ahead, sent when heard: its position is the one
        // heard now (played from the first block pushed, at 0).
        expect(report['position']! as double, closeTo(now, 1e-6));
      }
    }
    var reports = events
        .where((event) => event['type'] == MidiHostEvents.position)
        .toList();
    // Every 6 blocks of 256 frames, those heard by 1 s.
    expect(reports.length, inInclusiveRange(27, 30));
    expect(MidiTrackMeters.fromEvent(reports.last, 1)!.keys, [
      {60},
    ]);
  });
}

class _NullStream implements MidiPcmStream {
  @override
  bool push(Float32List frames) => true;

  @override
  int get exhaustCount => 0;

  @override
  void close() {}
}
