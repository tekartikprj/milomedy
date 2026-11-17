@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('the AudioWorklet player plays a SoundFont', () async {
    var response = await web.window.fetch(midiWorkletDefaultUrl.toJS).toDart;
    if (!response.ok) {
      markTestSkipped(
        '$midiWorkletDefaultUrl not built: run the VM tests first '
        '(dart test -p vm, then -p chrome)',
      );
      return;
    }
    const rate = 44100;
    var context = web.OfflineAudioContext(2.toJS, rate, rate);
    var player = await MidiWorkletPlayer.create(
      synths: [const MidiSynthSpec(soundFont: 'tiny')],
      context: context,
    );
    var errors = <String>[];
    player.onError.listen(errors.add);
    await player.loadSoundFont('tiny', midiTinySoundFontBytes());
    player.load(
      MidiTimeline(
        notes: const [MidiTimelineNote(start: 0, duration: 0.5, key: 69)],
      ),
    );
    await player.play();
    await player.sync();
    var buffer = await context.startRendering().toDart;
    var left = buffer.getChannelData(0).toDart;
    await player.sync();
    expect(errors, isEmpty);
    // The sine of the SoundFont, 440 Hz, rendered by melty in the audio
    // thread.
    var note = left.sublist(rate ~/ 100, rate ~/ 100 + rate ~/ 4);
    var crossings = 0;
    for (var i = 1; i < note.length; i++) {
      if ((note[i - 1] < 0) != (note[i] < 0)) {
        crossings++;
      }
    }
    expect(crossings * 4, closeTo(880, 10));
    await player.close();
  });

  test('tuned to 442 Hz, a dry track on the shared reverb', () async {
    var response = await web.window.fetch(midiWorkletDefaultUrl.toJS).toDart;
    if (!response.ok) {
      markTestSkipped('$midiWorkletDefaultUrl not built');
      return;
    }
    const rate = 44100;
    Future<List<double>> play({double send = 0}) async {
      var context = web.OfflineAudioContext(2.toJS, rate, rate);
      var player = await MidiWorkletPlayer.create(
        synths: [const MidiSynthSpec(soundFont: 'tiny', effects: false)],
        context: context,
      );
      var errors = <String>[];
      player.onError.listen(errors.add);
      await player.loadSoundFont('tiny', midiTinySoundFontBytes());
      player
        ..load(
          MidiTimeline(
            notes: const [MidiTimelineNote(start: 0, duration: 0.5, key: 69)],
          ),
        )
        ..tuneCents = 7.85
        ..setReverb(0, send);
      await player.play();
      await player.sync();
      var buffer = await context.startRendering().toDart;
      await player.sync();
      expect(errors, isEmpty);
      await player.close();
      return buffer.getChannelData(0).toDart;
    }

    var dry = await play();
    expect(_frequency(dry.sublist(441, rate ~/ 2), rate), closeTo(442, 0.05));
    var wet = await play(send: 1);
    // The tail after the release (0.5 s + 0.1 s).
    double peak(List<double> samples) =>
        samples.fold(0.0, (p, s) => s.abs() > p ? s.abs() : p);
    expect(peak(dry.sublist((0.7 * rate).round())), lessThan(1e-4));
    expect(peak(wet.sublist((0.7 * rate).round())), greaterThan(1e-3));
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
