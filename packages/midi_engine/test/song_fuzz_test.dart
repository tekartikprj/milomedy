import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:tekartik_midi/midi.dart';
import 'package:tekartik_midi/midi_writer.dart';
import 'package:test/test.dart';

const _ppq = 96;

MidiTrack _track(List<(int, MidiEvent)> events) {
  var track = MidiTrack();
  var tick = 0;
  for (var (at, event) in events) {
    track.addEvent(at - tick, event);
    tick = at;
  }
  track.addEvent(0, EndOfTrackEvent());
  return track;
}

/// A small song: tempo and time signature changes, notes on 2 channels.
Uint8List _bytes() {
  var file = MidiFile()
    ..fileFormat = 1
    ..ppq = _ppq;
  file.addTrack(
    _track([
      (0, TrackNameEvent(data: utf8.encode('C'))),
      (0, TempoEvent.bpm(120)),
      (0, TimeSigEvent.topBottom(3, 4)),
      (0, KeySigEvent(-1, 1)),
      (3 * _ppq, TempoEvent.bpm(60)),
      (3 * _ppq, TimeSigEvent.topBottom(4, 4)),
    ]),
  );
  file.addTrack(
    _track([
      (0, ProgramChangeEvent(0, 5)),
      (0, NoteOnEvent(0, 60, 100)),
      (_ppq, NoteOffEvent(0, 60, 0)),
      (_ppq, NoteOnEvent(9, 42, 100)),
      (2 * _ppq, NoteOffEvent(9, 42, 0)),
      (2 * _ppq, NoteOnEvent(0, 64, 100)),
      (4 * _ppq, NoteOffEvent(0, 64, 0)),
    ]),
  );
  return Uint8List.fromList(FileWriter.fileData(file));
}

/// Reads [bytes] as a song and uses it as an app does: a bad file is a
/// [FormatException] (or format 2 refused), never another error, an endless
/// loop or a huge allocation.
void _check(Uint8List bytes, String reason) {
  MidiSong song;
  try {
    song = MidiSong.fromBytes(bytes);
  } on FormatException {
    return;
  } on UnsupportedError catch (e) {
    expect('$e', contains('format 2'), reason: reason);
    return;
  }
  var duration = song.duration;
  var timeline = song.toTimeline(trackOf: (_, channel) => channel == 9 ? 1 : 0);
  song
    ..trackNames
    ..initialPrograms
    ..channels
    ..copyright;
  for (var tick in [0, song.lengthTicks ~/ 2, song.lengthTicks]) {
    song.barBeatAt(tick);
  }
  song
    ..tickOf(0)
    ..tickOf(2, 1);
  for (var seconds in [0.0, duration / 2, duration]) {
    song.barBeatAt(song.tickAt(seconds));
  }
  var engine = MidiEngine(
    sampleRate: 8000,
    synths: [
      DartSynth(sampleRate: 8000, instrument: ReedInstrument.treble()),
      DartSynth(sampleRate: 8000, percussion: const ClickInstrument()),
    ],
  );
  engine.load(timeline);
  for (var i = 0; i < 4; i++) {
    engine.render(2048);
  }
  engine.seek(duration / 2);
  engine.render(2048);
}

void main() {
  var timeout = const Timeout(Duration(minutes: 1));
  var bytes = _bytes();

  test('every truncation', () {
    for (var length = 0; length < bytes.length; length++) {
      expect(
        () => MidiSong.fromBytes(bytes.sublist(0, length)),
        throwsFormatException,
        reason: 'length $length',
      );
    }
    _check(bytes, 'whole');
  }, timeout: timeout);

  test('every byte changed', () {
    for (var i = 0; i < bytes.length; i++) {
      for (var value in [0, 1, 2, 0x3f, 0x40, 0x7f, 0x80, 0xff]) {
        _check(Uint8List.fromList(bytes)..[i] = value, 'byte $i = $value');
      }
    }
  }, timeout: timeout);

  test('random changes', () {
    var random = Random(1);
    for (var n = 0; n < 3000; n++) {
      var copy = Uint8List.fromList(bytes);
      for (var k = 0; k <= random.nextInt(4); k++) {
        copy[random.nextInt(copy.length)] = random.nextInt(256);
      }
      _check(copy, 'mutation $n');
    }
  }, timeout: timeout);
}
