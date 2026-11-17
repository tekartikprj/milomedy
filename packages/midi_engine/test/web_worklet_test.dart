@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:math' as math;

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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

/// The module built by test/setup_web_worklet_test.dart (run on the VM
/// before the browser tests), null when missing.
Future<bool> _moduleBuilt() async {
  var response = await web.window.fetch(midiWorkletDefaultUrl.toJS).toDart;
  return response.ok;
}

void main() {
  test('the engine plays in an AudioWorklet', () async {
    if (!await _moduleBuilt()) {
      markTestSkipped(
        '$midiWorkletDefaultUrl not built: run the VM tests first '
        '(dart test -p vm, then -p chrome)',
      );
      return;
    }
    const rate = 44100;
    var context = web.OfflineAudioContext(2.toJS, 2 * rate, rate);
    var player = await MidiWorkletPlayer.create(
      synths: [MidiSynthSpec.metronome],
      context: context,
    );
    var errors = <String>[];
    player.onError.listen(errors.add);
    var states = <MidiPlayerState>[];
    player.onState.listen(states.add);
    var timeline = midiMetronomeTimeline(bpm: 120, beats: 2);
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..setVolume(0, 0.5);
    await player.play();
    // Handled by the worklet before rendering starts.
    await player.sync();
    var buffer = await context.startRendering().toDart;
    var left = buffer.getChannelData(0).toDart;
    var right = buffer.getChannelData(1).toDart;
    // A click every half second, rendered by Dart in the audio thread (a
    // sine: its first sample is 0).
    expect(_onsets(left), [for (var i = 0; i < 4; i++) i * rate ~/ 2 + 1]);
    expect(right, left);
    var peak = left.fold(0.0, (p, s) => math.max(p, s.abs()));
    expect(peak, inExclusiveRange(0.05, midiLimit));
    await player.sync();
    expect(errors, isEmpty);
    // An error in the worklet comes back as an error event.
    player.sendCommand({'type': 'nope'});
    await player.sync();
    expect(errors.single, contains('nope'));
    expect(player.state, MidiPlayerState.playing);
    // The stopped event of the load, sent before the play, is stale.
    expect(states, [MidiPlayerState.playing]);
    await player.close();
  });

  group('phase 2 features', () {
    const rate = 44100;

    /// A player of [synths] on an offline context of [seconds], set by
    /// [setUp], rendered: the left channel.
    Future<(MidiWorkletPlayer, List<double>)?> render(
      double seconds,
      List<MidiSynthSpec> synths,
      Future<void> Function(MidiWorkletPlayer player) setUp,
    ) async {
      if (!await _moduleBuilt()) {
        markTestSkipped('$midiWorkletDefaultUrl not built');
        return null;
      }
      var context = web.OfflineAudioContext(
        2.toJS,
        (seconds * rate).round(),
        rate,
      );
      var player = await MidiWorkletPlayer.create(
        synths: synths,
        context: context,
      );
      var errors = <String>[];
      player.onError.listen(errors.add);
      await setUp(player);
      await player.play();
      await player.sync();
      var buffer = await context.startRendering().toDart;
      await player.sync();
      expect(errors, isEmpty);
      return (player, buffer.getChannelData(0).toDart);
    }

    test('the speed trainer: each step at the loop start', () async {
      var timeline = midiMetronomeTimeline(bpm: 120, beats: 2);
      var speeds = <double>[];
      var result = await render(3, [MidiSynthSpec.metronome], (player) async {
        player
          ..onSpeed.listen(speeds.add)
          ..load(timeline)
          ..setLoop(timeline.start, timeline.end)
          ..setSpeedTrainer(from: 1, to: 2, step: 0.5);
      });
      if (result == null) {
        return;
      }
      var (player, left) = result;
      // A pass at 1 (44100 frames), at 1.5 (29400), then at 2.
      expect(_onsets(left).sublist(0, 6), [
        1,
        rate ~/ 2 + 1,
        rate + 1,
        rate + 14700 + 1,
        rate + 29400 + 1,
        rate + 29400 + 11025 + 1,
      ]);
      expect(speeds, [1.5, 2]);
      expect(player.speed, 2);
      await player.close();
    });

    test('the reverb: a tail after the click', () async {
      var click = MidiTimeline(
        notes: const [
          MidiTimelineNote(
            start: 0,
            duration: 0.05,
            key: midiKeyHiWoodBlock,
            channel: midiPercussionChannel,
          ),
        ],
        end: 1,
      );
      Future<List<double>?> play(double send) async {
        var result = await render(0.5, [MidiSynthSpec.metronome], (
          player,
        ) async {
          player
            ..load(click)
            ..setReverb(0, send);
        });
        await result?.$1.close();
        return result?.$2;
      }

      var dry = await play(0);
      var wet = await play(1);
      if (dry == null || wet == null) {
        return;
      }
      double peak(List<double> samples) =>
          samples.fold(0.0, (p, s) => math.max(p, s.abs()));
      // The click lasts 60 ms.
      expect(peak(dry.sublist(rate ~/ 10)), 0);
      expect(peak(wet.sublist(rate ~/ 10)), greaterThan(0.001));
    });

    test('the meters: levels and keys while playing', () async {
      var meters = <MidiTrackMeters>[];
      var result = await render(
        1,
        [
          MidiSynthSpec.metronome,
          const MidiSynthSpec(instrument: MidiInstrumentIds.reed),
        ],
        (player) async {
          player
            ..onMeters.listen(meters.add)
            ..load(
              MidiTimeline(
                notes: const [
                  MidiTimelineNote(start: 0, duration: 2, key: 60, track: 1),
                ],
              ),
            )
            ..transpose = 2;
        },
      );
      if (result == null) {
        return;
      }
      var (player, _) = result;
      // About 30 a second.
      expect(meters.length, inInclusiveRange(25, 31));
      expect(player.soundingKeys, [
        <int>{},
        {62},
      ]);
      expect(player.trackLevels[0], 0);
      expect(player.trackLevels[1], greaterThan(0.05));
      await player.close();
    });

    test('the tuning: a Dart synth at 442 Hz', () async {
      var result = await render(
        0.5,
        [const MidiSynthSpec(instrument: MidiInstrumentIds.reed)],
        (player) async {
          player
            ..load(
              MidiTimeline(
                notes: const [MidiTimelineNote(start: 0, duration: 2, key: 69)],
              ),
            )
            ..tuneCents = 7.85;
        },
      );
      if (result == null) {
        return;
      }
      var (player, left) = result;
      expect(player.tuneCents, 7.85);
      // The reed: its rising zero crossings, once a period.
      expect(_frequency(left.sublist(rate ~/ 10), rate), closeTo(442, 0.1));
      await player.close();
    });
  });
}

/// The frequency of the rising zero crossings of [samples] (interpolated).
double _frequency(List<double> samples, int rate) {
  double? first;
  var last = 0.0;
  var count = 0;
  for (var i = 1; i < samples.length; i++) {
    var a = samples[i - 1];
    var b = samples[i];
    if (a < 0 && b >= 0) {
      var at = i - 1 + a / (a - b);
      first ??= at;
      last = at;
      count++;
    }
  }
  return (count - 1) * rate / (last - first!);
}
