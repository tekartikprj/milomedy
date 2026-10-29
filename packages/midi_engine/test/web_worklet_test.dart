@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:math' as math;

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';
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
    expect(player.state, MidiPlayerState.playing);
    await player.close();
  });
}
