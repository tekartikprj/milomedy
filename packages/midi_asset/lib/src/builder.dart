/// The song builder: parts of notes in beats (quarter notes), written as a
/// format 1 MIDI file, a conductor track then a track per part.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:tekartik_midi/midi.dart';
import 'package:tekartik_midi/midi_writer.dart';

/// The ticks of a quarter note.
const midiAssetPpq = 480;

/// The General MIDI percussion channel.
const midiAssetDrumChannel = 9;

/// A note of a part.
class MidiAssetNote {
  /// The start, in beats (quarter notes).
  final double beat;

  /// The length, in beats.
  final double beats;

  /// The key.
  final int key;

  /// The velocity.
  final int velocity;

  /// A note.
  const MidiAssetNote(this.beat, this.beats, this.key, this.velocity);
}

/// A part: an instrument on a channel.
class MidiAssetPart {
  /// Its name (the track name).
  final String name;

  /// Its channel, 0 to 15.
  final int channel;

  /// Its General MIDI program, 0 to 127 (ignored on the drum channel).
  final int program;

  /// Its volume (controller 7).
  final int volume;

  /// Its pan (controller 10), 0 left, 64 middle, 127 right.
  final int pan;

  /// Its reverb send (controller 91).
  final int reverb;

  /// Its notes.
  final notes = <MidiAssetNote>[];

  MidiAssetPart._(
    this.name,
    this.channel,
    this.program,
    this.volume,
    this.pan,
    this.reverb,
  );

  /// Adds a note of [key] from [beat], [beats] long.
  void note(double beat, double beats, int key, [int velocity = 90]) {
    if (key < 0 || key > 127 || beats <= 0) {
      return;
    }
    notes.add(MidiAssetNote(beat, beats, key, velocity.clamp(1, 127)));
  }

  /// Adds [keys] together.
  void chord(double beat, double beats, List<int> keys, [int velocity = 80]) {
    for (var key in keys) {
      note(beat, beats, key, velocity);
    }
  }
}

/// A song being built.
class MidiAssetSongBuilder {
  /// The title.
  final String title;

  /// The tempo, in quarter notes per minute.
  final double bpm;

  /// The beats (quarter notes) in a bar: 4 for 4/4, 3 for 3/4, 2 for 2/4.
  final int beatsPerBar;

  /// The key signature: sharps (positive) or flats (negative).
  final int keyAlterations;

  /// A minor key.
  final bool minor;

  /// The parts.
  final parts = <MidiAssetPart>[];

  /// A song.
  MidiAssetSongBuilder({
    required this.title,
    required this.bpm,
    this.beatsPerBar = 4,
    this.keyAlterations = 0,
    this.minor = false,
  });

  /// The first beat of [bar] (from 0).
  double bar(int bar) => (bar * beatsPerBar).toDouble();

  /// A new part.
  MidiAssetPart part(
    String name, {
    required int channel,
    int program = 0,
    int volume = 100,
    int pan = 64,
    int reverb = 40,
  }) {
    var part = MidiAssetPart._(name, channel, program, volume, pan, reverb);
    parts.add(part);
    return part;
  }

  /// The length, in beats: the end of the last note.
  double get length {
    var end = 0.0;
    for (var part in parts) {
      for (var note in part.notes) {
        if (note.beat + note.beats > end) {
          end = note.beat + note.beats;
        }
      }
    }
    return end;
  }

  /// The MIDI file.
  MidiFile toMidiFile() {
    var file = MidiFile()
      ..fileFormat = MidiFile.formatMultiTrack
      ..ppq = midiAssetPpq;
    var end = _ticks(length) + midiAssetPpq;
    file.addTrack(
      _track(end, [
        (0, 0, TrackNameEvent(data: utf8.encode(title))),
        (
          0,
          0,
          MetaEvent(
            0x02,
            utf8.encode('milomedy_midi_asset (MIT), made in Dart'),
          ),
        ),
        (0, 0, TempoEvent.bpm(bpm)),
        (0, 0, TimeSigEvent.topBottom(beatsPerBar, 4)),
        (0, 0, KeySigEvent(keyAlterations, minor ? 1 : 0)),
      ]),
    );
    for (var part in parts) {
      var channel = part.channel;
      var events = <(int, int, MidiEvent)>[
        (0, 0, TrackNameEvent(data: utf8.encode(part.name))),
        if (channel != midiAssetDrumChannel)
          (0, 0, ProgramChangeEvent(channel, part.program)),
        (0, 0, ControlChangeEvent.withParam(channel, 7, part.volume)),
        (0, 0, ControlChangeEvent.withParam(channel, 10, part.pan)),
        (0, 0, ControlChangeEvent.withParam(channel, 91, part.reverb)),
      ];
      // A note of a key cut where the same key starts again. Notes starting
      // together in the order added: List.sort is not stable on the VM.
      var notes = [
        for (var (_, note)
            in (part.notes.indexed.toList()..sort((a, b) {
              var byBeat = a.$2.beat.compareTo(b.$2.beat);
              return byBeat != 0 ? byBeat : a.$1 - b.$1;
            })))
          note,
      ];
      var nextStart = <int, int>{};
      for (var note in notes.reversed) {
        var start = _ticks(note.beat);
        var stop = _ticks(note.beat + note.beats);
        var next = nextStart[note.key];
        if (next != null && next < stop) {
          stop = next;
        }
        nextStart[note.key] = start;
        if (stop <= start) {
          continue;
        }
        // The note offs first at the same tick.
        events
          ..add((start, 2, NoteOnEvent(channel, note.key, note.velocity)))
          ..add((stop, 1, NoteOffEvent(channel, note.key, 0)));
      }
      file.addTrack(_track(end, events));
    }
    return file;
  }

  /// The bytes of the MIDI file.
  Uint8List toBytes() => Uint8List.fromList(FileWriter.fileData(toMidiFile()));

  static int _ticks(double beats) => (beats * midiAssetPpq).round();

  /// A track of [events] (tick, order at the same tick, event), ended at
  /// [end].
  static MidiTrack _track(int end, List<(int, int, MidiEvent)> events) {
    var indexed = events.indexed.toList()
      ..sort((a, b) {
        var (ia, (ta, oa, _)) = a;
        var (ib, (tb, ob, _)) = b;
        if (ta != tb) {
          return ta - tb;
        }
        if (oa != ob) {
          return oa - ob;
        }
        return ia - ib;
      });
    var track = MidiTrack();
    var tick = 0;
    for (var (_, (at, _, event)) in indexed) {
      track.addEvent(at - tick, event);
      tick = at;
    }
    track.addEvent(end > tick ? end - tick : 0, EndOfTrackEvent());
    return track;
  }
}
