@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/isolate_player.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';

const _rate = 44100;

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

MidiPcmStreamOpener _captureTo(SendPort port) =>
    (sampleRate) => _CaptureStream(port);

void main() {
  test('the isolate player plays a SoundFont', () async {
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
      synths: [const MidiSynthSpec(soundFont: 'tiny')],
      openStream: _captureTo(captured.sendPort),
      setup: midiSoundFontRegister,
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
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await player.close();
    await closed.future;
    captured.close();
    expect(errors, isEmpty);
    // The sine of the SoundFont: 440 Hz, 880 zero crossings a second.
    var start = left.indexWhere((sample) => sample.abs() > 1e-4);
    expect(start, greaterThanOrEqualTo(0));
    var note = left.sublist(start + 441, start + 441 + _rate ~/ 4);
    var crossings = 0;
    for (var i = 1; i < note.length; i++) {
      if ((note[i - 1] < 0) != (note[i] < 0)) {
        crossings++;
      }
    }
    expect(crossings * 4, closeTo(880, 10));
  });
}
