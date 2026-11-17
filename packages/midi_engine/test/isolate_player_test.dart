@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/isolate_player.dart';
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

/// A stream sending what is pushed to the test isolate.
class _CaptureStream implements MidiPcmStream {
  final SendPort port;

  _CaptureStream(this.port);

  @override
  bool push(Float32List frames) {
    port.send(frames);
    return true;
  }

  @override
  int get exhaustCount => 0;

  @override
  void close() => port.send('closed');
}

MidiPcmStream _failing(int sampleRate) => throw StateError('no audio device');

/// An opener sending to [port]: a closure created here captures only the
/// port, so the isolate can receive it.
MidiPcmStreamOpener _captureTo(SendPort port) =>
    (sampleRate) => _CaptureStream(port);

void main() {
  test('plays in a background isolate, tells the position heard', () async {
    var captured = ReceivePort();
    var left = <double>[];
    var closed = Completer<void>();
    captured.listen((message) {
      if (message is Float32List) {
        for (var i = 0; i < message.length; i += 2) {
          left.add(message[i]);
        }
      } else if (message == 'closed') {
        closed.complete();
      }
    });
    var player = await MidiIsolatePlayer.spawn(
      synths: [MidiSynthSpec.metronome],
      sampleRate: _rate,
      openStream: _captureTo(captured.sendPort),
    );
    var states = <MidiPlayerState>[];
    player.onState.listen(states.add);
    var timeline = midiMetronomeTimeline(bpm: 120, beats: 2);
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end);
    await player.play();
    await player.sync();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // Heard about 1.2 s in (the frames are pushed 0.1 s ahead), in the loop.
    expect(player.position, inInclusiveRange(0, 1));
    player.pause();
    await player.sync();
    await player.close();
    await closed.future;
    captured.close();
    // A click every half second, wherever the first one fell.
    var onsets = _onsets(left);
    expect(onsets.length, greaterThanOrEqualTo(3));
    for (var i = 1; i < onsets.length; i++) {
      expect(onsets[i] - onsets[i - 1], _rate ~/ 2);
    }
    expect(states, [MidiPlayerState.playing, MidiPlayerState.paused]);
  });

  test('meters, the speed trainer, the reverb and the tuning', () async {
    var captured = ReceivePort();
    var closed = Completer<void>();
    var left = <double>[];
    captured.listen((message) {
      if (message is Float32List) {
        for (var i = 0; i < message.length; i += 2) {
          left.add(message[i]);
        }
      } else if (message == 'closed') {
        closed.complete();
      }
    });
    var player = await MidiIsolatePlayer.spawn(
      synths: [
        MidiSynthSpec.metronome,
        const MidiSynthSpec(instrument: MidiInstrumentIds.reed),
      ],
      sampleRate: _rate,
      openStream: _captureTo(captured.sendPort),
    );
    var errors = <String>[];
    player.onError.listen(errors.add);
    var meters = <MidiTrackMeters>[];
    player.onMeters.listen(meters.add);
    var speeds = <double>[];
    player.onSpeed.listen(speeds.add);
    var timeline = MidiTimeline(
      notes: [
        ...midiMetronomeTimeline(bpm: 240, beats: 2).notes,
        const MidiTimelineNote(start: 0, duration: 0.5, key: 60, track: 1),
      ],
      start: 0,
      end: 0.5,
    );
    player
      ..load(timeline)
      ..setLoop(0, 0.5)
      ..setSpeedTrainer(from: 1, to: 1.5, step: 0.25)
      ..setReverb(1, 0.5)
      ..reverbLevel = 0.8
      ..tuneCents = 10;
    await player.play();
    await player.sync();
    // The last step is heard about 1 s in.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(player.soundingKeys[1], {60});
    expect(player.trackLevels[1], greaterThan(0));
    // A pass at 1, one at 1.25, then 1.5.
    expect(speeds, [1.25, 1.5]);
    expect(player.speed, 1.5);
    player.pause();
    await player.sync();
    expect(player.meters.isSilent, isTrue);
    await player.close();
    await closed.future;
    captured.close();
    expect(errors, isEmpty);
    expect(meters.length, greaterThan(5));
    expect(left.any((sample) => sample != 0), isTrue);
  });

  test('the stream cannot be opened', () async {
    await expectLater(
      MidiIsolatePlayer.spawn(
        synths: [MidiSynthSpec.metronome],
        openStream: _failing,
      ),
      throwsStateError,
    );
  });
}
