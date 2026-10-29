import 'dart:convert';
import 'dart:math' as math;

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:tekartik_midi/midi.dart';
import 'package:tekartik_midi/midi_writer.dart';
import 'package:test/test.dart';

const _ppq = 480;

/// A track of [events] at their absolute ticks, ended at the last one.
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

/// The bytes of a file of [tracks], written and read back by the song.
MidiSong _song(List<MidiTrack> tracks, {int ppq = _ppq, int format = 1}) {
  var file = MidiFile()
    ..fileFormat = format
    ..ppq = ppq;
  tracks.forEach(file.addTrack);
  return MidiSong.fromBytes(FileWriter.fileData(file));
}

/// A song: 120 bpm then 60 bpm from bar 2 (3/4, then 4/4 from bar 2),
/// a melody on channel 0 and a bass on channel 1 of track 1.
MidiSong _demo() => _song([
  _track([
    (0, TrackNameEvent(data: utf8.encode('Conductor'))),
    (0, MetaEvent(MidiSongText.copyright, utf8.encode('© tekartik'))),
    (0, TempoEvent.bpm(120)),
    (0, TimeSigEvent.topBottom(3, 4)),
    (0, KeySigEvent(-1, 1)),
    (2 * 3 * _ppq, TempoEvent.bpm(60)),
    (2 * 3 * _ppq, TimeSigEvent.topBottom(4, 4)),
    (2 * 3 * _ppq, MetaEvent(MidiSongText.marker, utf8.encode('B'))),
  ]),
  _track([
    (0, TrackNameEvent(data: utf8.encode('Piano'))),
    (0, ProgramChangeEvent(0, 5)),
    (0, ControlChangeEvent.withParam(0, midiControllerVolume, 90)),
    (0, NoteOnEvent(0, 60, 100)),
    (0, NoteOnEvent(1, 36, 80)),
    // A lyric in Windows-1252: an apostrophe (0x92).
    (0, MetaEvent(MidiSongText.lyric, [0x4C, 0x92, 0x61, 0x6D])),
    (_ppq, NoteOffEvent(0, 60, 0)),
    // The same key off and on at the same tick, on in the file first.
    (2 * _ppq, NoteOnEvent(0, 62, 100)),
    (3 * _ppq, NoteOnEvent(0, 62, 90)),
    (3 * _ppq, NoteOnEvent(0, 62, 0)),
    (3 * _ppq, NoteOffEvent(1, 36, 0)),
    (4 * _ppq, PitchWheelChangeEvent(0, 0, 0x50)),
    (4 * _ppq, NoteOffEvent(0, 62, 0)),
    (6 * _ppq, ProgramChangeEvent(0, 7)),
    // Never released.
    (6 * _ppq, NoteOnEvent(0, 64, 100)),
    (7 * _ppq, NoteOnEvent(1, 38, 0)),
  ]),
]);

void main() {
  group('tempo map', () {
    test('ticks to seconds and back, tempo changes', () {
      var map = MidiTempoMap(
        ppq: _ppq,
        tempos: const [
          MidiTempo(960, 1000000),
          MidiTempo(0, 500000),
          MidiTempo(960, 250000),
        ],
      );
      // The last one at the same tick.
      expect(map.tempos, hasLength(2));
      expect(map.tempoAt(1000).bpm, 240);
      expect(map.secondsOf(480), 0.5);
      expect(map.secondsOf(960), 1);
      expect(map.secondsOf(1440), 1.25);
      expect(map.tickAt(0.5), 480);
      expect(map.tickAt(1.25), 1440);
      expect(map.tickAt(1.125), 1200);
      for (var tick = 0; tick < 3000; tick += 37) {
        expect(map.tickAt(map.secondsOf(tick)), closeTo(tick, 1e-6));
      }
    });

    test('120 bpm before the first tempo, or without one', () {
      var map = MidiTempoMap(ppq: 96, tempos: const [MidiTempo(192, 1000000)]);
      expect(map.tempos.first.bpm, 120);
      expect(map.secondsOf(192), 1);
      expect(map.secondsOf(288), 2);
      expect(MidiTempoMap(ppq: 96).secondsOf(96), 0.5);
      expect(() => MidiTempoMap(ppq: 0), throwsArgumentError);
    });

    test('SMPTE: a fixed number of ticks per second', () {
      var map = MidiTempoMap.smpte(1000);
      expect(map.isSmpte, isTrue);
      expect(map.secondsOf(500), 0.5);
      expect(map.tickAt(2), 2000);
      expect(map.tempoAt(10).bpm, 120);
    });
  });

  group('song', () {
    test('notes paired, at their ticks', () {
      var song = _demo();
      expect(song.format, 1);
      expect(song.fileTrackCount, 2);
      expect(
        [
          for (var note in song.notes)
            (note.tick, note.ticks, note.channel, note.key, note.velocity),
        ],
        [
          (0, _ppq, 0, 60, 100),
          (0, 3 * _ppq, 1, 36, 80),
          // Released by the note on with velocity 0, before the new one.
          (2 * _ppq, _ppq, 0, 62, 100),
          (3 * _ppq, _ppq, 0, 62, 90),
          // Ends with the song.
          (6 * _ppq, _ppq, 0, 64, 100),
        ],
      );
      expect(song.notes.first.fileTrack, 1);
      expect(song.lengthTicks, 7 * _ppq);
    });

    test('messages, texts, signatures', () {
      var song = _demo();
      expect(
        [
          for (var message in song.messages)
            (message.tick, message.status, message.data1, message.data2),
        ],
        [
          (0, midiProgramChange, 5, 0),
          (0, midiControlChange, midiControllerVolume, 90),
          (4 * _ppq, midiPitchBend, 0, 0x50),
          (6 * _ppq, midiProgramChange, 7, 0),
        ],
      );
      expect(song.trackNames, ['Conductor', 'Piano']);
      expect(song.copyright, '© tekartik');
      expect(song.lyrics.single.value, 'L’am');
      expect(song.markers.single.tick, 6 * _ppq);
      expect(song.channels, [0, 1]);
      expect(song.initialPrograms, {0: 5, 1: 0});
      expect(
        [
          for (var signature in song.timeSignatures)
            (signature.tick, signature.top, signature.bottom),
        ],
        [(0, 3, 4), (6 * _ppq, 4, 4)],
      );
      var key = song.keySignatures.single;
      expect((key.alterations, key.minor), (-1, true));
    });

    test('seconds with the tempo map', () {
      var song = _demo();
      // 6 quarters at 120 bpm, then 1 at 60 bpm.
      expect(song.secondsOf(6 * _ppq), 3);
      expect(song.duration, 4);
      expect(song.tickAt(3.5), 6.5 * _ppq);
    });

    test('bars and beats', () {
      var song = _demo();
      expect(song.barBeatAt(0), const MidiBarBeat(0, 0));
      expect(song.barBeatAt(4 * _ppq), const MidiBarBeat(1, 1));
      expect(song.barBeatAt(4.5 * _ppq), const MidiBarBeat(1, 1, 0.5));
      // 4/4 from bar 2.
      expect(song.barBeatAt(6 * _ppq), const MidiBarBeat(2, 0));
      expect(song.barBeatAt(13 * _ppq), const MidiBarBeat(3, 3));
      expect(song.tickOf(1, 2), 5 * _ppq);
      expect(song.tickOf(3, 3), 13 * _ppq);
    });

    test('6/8: an eighth note a beat', () {
      var song = _song([
        _track([
          (0, TimeSigEvent.topBottom(6, 8)),
          (0, NoteOnEvent(0, 60, 100)),
          (_ppq * 3, NoteOffEvent(0, 60, 0)),
        ]),
      ], format: 0);
      expect(song.barBeatAt(_ppq * 3), const MidiBarBeat(1, 0));
      expect(song.barBeatAt(_ppq / 2), const MidiBarBeat(0, 1));
    });

    test('no time signature: 4/4', () {
      var song = _song([
        _track([
          (0, NoteOnEvent(0, 60, 100)),
          (_ppq * 5, NoteOffEvent(0, 60, 0)),
        ]),
      ]);
      expect(song.timeSignatures.single.top, 4);
      expect(song.barBeatAt(_ppq * 5), const MidiBarBeat(1, 1));
      expect(song.trackNames, [null]);
      expect(song.copyright, isNull);
    });

    test('SMPTE division: the tempo ignored', () {
      var file = MidiFile()..setFrameDivision(25, 40);
      file.addTrack(
        _track([
          (0, TempoEvent.bpm(60)),
          (0, NoteOnEvent(0, 60, 100)),
          (500, NoteOffEvent(0, 60, 0)),
        ]),
      );
      var song = MidiSong.fromBytes(FileWriter.fileData(file));
      expect(song.tempoMap.isSmpte, isTrue);
      expect(song.duration, 0.5);
      expect(song.toTimeline().notes.single.duration, 0.5);
    });

    test('format 2 is refused', () {
      var file = MidiFile()..fileFormat = 2;
      file.addTrack(_track([]));
      expect(() => MidiSong.fromFile(file), throwsUnsupportedError);
    });

    test('text decoding', () {
      expect(midiDecodeText(utf8.encode('été')), 'été');
      expect(midiDecodeText([0xE9, 0x20, 0x80, 0x9D]), 'é €\u009D');
    });
  });

  group('timeline', () {
    test('seconds, messages, tracks', () {
      var timeline = _demo().toTimeline(
        trackOf: (fileTrack, channel) => channel,
      );
      expect(timeline.start, 0);
      expect(timeline.end, 4);
      expect(timeline.trackCount, 2);
      expect(
        [
          for (var note in timeline.notes)
            (note.start, note.duration, note.track, note.key),
        ],
        [
          (0, 0.5, 0, 60),
          (0, 1.5, 1, 36),
          (1, 0.5, 0, 62),
          (1.5, 0.5, 0, 62),
          // After the tempo change: a quarter lasts a second.
          (3, 1, 0, 64),
        ],
      );
      expect(
        [for (var message in timeline.messages) (message.time, message.status)],
        [
          (0, midiProgramChange),
          (0, midiControlChange),
          (2, midiPitchBend),
          (3, midiProgramChange),
        ],
      );
    });

    test('a program override drops the channel\'s program changes', () {
      var timeline = _demo().toTimeline(programs: {0: 21});
      expect(
        [
          for (var message in timeline.messages)
            if ((message.status & 0xf0) == midiProgramChange)
              (message.time, message.channel, message.data1),
        ],
        [(0, 0, 21)],
      );
    });

    test('played by the engine, each note at its frame', () {
      const rate = 8000;
      var song = _demo();
      var engine = MidiEngine(
        sampleRate: rate,
        synths: [
          DartSynth(sampleRate: rate, instrument: ReedInstrument.treble()),
        ],
      );
      engine.load(song.toTimeline(trackOf: (_, channel) => channel));
      // Only channel 0 has a synth: the bass is ignored.
      var samples = engine.render(5 * rate).left.single;
      double peak(int from, int to) =>
          samples.sublist(from, to).fold(0.0, (p, s) => math.max(p, s.abs()));
      // The first note, then silence after its release.
      expect(peak(0, 100), greaterThan(0));
      expect(peak((0.6 * rate).round(), rate), 0);
      // The note at 1 s.
      expect(samples[rate - 1], 0);
      expect(samples[rate + 1], isNot(0));
      // The last note, at 3 s, until 4 s.
      expect(peak((2.1 * rate).round(), 3 * rate), 0);
      expect(peak(3 * rate, 4 * rate), greaterThan(0));
      expect(peak((4.1 * rate).round(), 5 * rate), 0);
    });
  });
}
