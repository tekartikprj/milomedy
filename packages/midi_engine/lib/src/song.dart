/// A MIDI file loaded for playing: its notes (each note on paired with its
/// note off), its other channel messages, its texts, its tempo map and its
/// signatures, all at absolute ticks; and the timeline the engine plays.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:tekartik_midi/midi.dart';
import 'package:tekartik_midi/midi_parser.dart';

import 'tempo_map.dart';
import 'timeline.dart';

/// A note of a song.
class MidiSongNote {
  /// The tick of its note on.
  final int tick;

  /// Its length, in ticks.
  final int ticks;

  /// The track of the file it is in.
  final int fileTrack;

  /// The channel, 0 to 15.
  final int channel;

  /// The key, 0 to 127.
  final int key;

  /// The velocity, 1 to 127.
  final int velocity;

  /// A note.
  const MidiSongNote({
    required this.tick,
    required this.ticks,
    required this.key,
    this.velocity = 100,
    this.channel = 0,
    this.fileTrack = 0,
  });

  /// The tick of its note off.
  int get endTick => tick + ticks;

  @override
  String toString() =>
      'MidiSongNote($tick, $ticks, $key, channel $channel, '
      'track $fileTrack)';
}

/// A channel message of a song other than the notes: a controller, a
/// program, a pitch bend, an aftertouch.
class MidiSongMessage {
  /// The tick.
  final int tick;

  /// The track of the file it is in.
  final int fileTrack;

  /// The status, its channel in the low 4 bits.
  final int status;

  /// The first data byte.
  final int data1;

  /// The second data byte (0 when the message has one).
  final int data2;

  /// A message.
  const MidiSongMessage({
    required this.tick,
    required this.status,
    required this.data1,
    this.data2 = 0,
    this.fileTrack = 0,
  });

  /// The channel.
  int get channel => status & 0x0f;

  @override
  String toString() =>
      'MidiSongMessage($tick, 0x${status.toRadixString(16)}, $data1, $data2)';
}

/// A text meta event of a song: kept as its bytes, as the encoding of most
/// `.kar` files is not UTF-8.
class MidiSongText {
  /// A text event (the syllables of `.kar` files).
  static const text = 0x01;

  /// A copyright notice.
  static const copyright = 0x02;

  /// A track name.
  static const trackName = 0x03;

  /// A lyric (RP-017).
  static const lyric = 0x05;

  /// A marker.
  static const marker = 0x06;

  /// A cue point.
  static const cue = 0x07;

  /// The tick.
  final int tick;

  /// The track of the file it is in.
  final int fileTrack;

  /// The meta event type: [text], [copyright], [trackName], [lyric],
  /// [marker], [cue] or another text type up to 0x0F.
  final int type;

  /// The bytes.
  final List<int> bytes;

  /// A text.
  const MidiSongText({
    required this.tick,
    required this.type,
    required this.bytes,
    this.fileTrack = 0,
  });

  /// The text: UTF-8, or Windows-1252 when the bytes are not UTF-8.
  String get value => midiDecodeText(bytes);

  @override
  String toString() => 'MidiSongText($tick, $type, $value)';
}

/// A time signature from its tick (a bar line).
class MidiTimeSignature {
  /// The tick.
  final int tick;

  /// The beats in a bar.
  final int top;

  /// The note value of a beat (4 for a quarter note).
  final int bottom;

  /// A time signature.
  const MidiTimeSignature(this.tick, this.top, this.bottom);

  @override
  String toString() => 'MidiTimeSignature($tick, $top/$bottom)';
}

/// A key signature from its tick.
class MidiKeySignature {
  /// The tick.
  final int tick;

  /// The sharps (positive) or flats (negative), -7 to 7.
  final int alterations;

  /// A minor key.
  final bool minor;

  /// A key signature.
  const MidiKeySignature(this.tick, this.alterations, {this.minor = false});

  @override
  String toString() =>
      'MidiKeySignature($tick, $alterations${minor ? ' minor' : ''})';
}

/// A place in bars and beats, counted from 0.
class MidiBarBeat {
  /// The bar.
  final int bar;

  /// The beat in the bar.
  final int beat;

  /// The fraction of the beat, 0 to 1.
  final double fraction;

  /// A place.
  const MidiBarBeat(this.bar, this.beat, [this.fraction = 0]);

  @override
  bool operator ==(Object other) =>
      other is MidiBarBeat &&
      other.bar == bar &&
      other.beat == beat &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(bar, beat, fraction);

  @override
  String toString() => 'MidiBarBeat($bar, $beat, $fraction)';
}

/// A song.
class MidiSong {
  /// The format of the file (0 or 1).
  final int format;

  /// The tempo map.
  final MidiTempoMap tempoMap;

  /// The notes, by tick.
  final List<MidiSongNote> notes;

  /// The other channel messages, by tick.
  final List<MidiSongMessage> messages;

  /// The text meta events, by tick.
  final List<MidiSongText> texts;

  /// The time signatures, by tick, the first one at tick 0 (4/4 when the
  /// file has none there).
  final List<MidiTimeSignature> timeSignatures;

  /// The key signatures, by tick.
  final List<MidiKeySignature> keySignatures;

  /// The number of tracks in the file.
  final int fileTrackCount;

  /// The last tick of the file (its last event, the end of its tracks).
  final int lengthTicks;

  MidiSong._({
    required this.format,
    required this.tempoMap,
    required this.notes,
    required this.messages,
    required this.texts,
    required this.timeSignatures,
    required this.keySignatures,
    required this.fileTrackCount,
    required this.lengthTicks,
  });

  /// The song of the bytes of a MIDI file.
  factory MidiSong.fromBytes(List<int> bytes) =>
      MidiSong.fromFile(FileParser.dataFile(bytes)!);

  /// The song of [file]. Format 2 (independent sequences) is refused.
  factory MidiSong.fromFile(MidiFile file) {
    if (file.fileFormat == 2) {
      throw UnsupportedError('MIDI file format 2 is not supported');
    }
    var events = <_Event>[];
    var lengthTicks = 0;
    for (var (trackIndex, track) in file.tracks.indexed) {
      var tick = 0;
      for (var (order, trackEvent) in track.events.indexed) {
        tick += trackEvent.deltaTime;
        events.add(_Event(tick, trackIndex, order, trackEvent.midiEvent));
      }
      lengthTicks = math.max(lengthTicks, tick);
    }
    // By tick, the note offs first (a note off and a note on of the same key
    // at the same tick), then by track and order in the file.
    events.sort((a, b) {
      var byTick = a.tick.compareTo(b.tick);
      if (byTick != 0) {
        return byTick;
      }
      var byOff = (a.isNoteOff ? 0 : 1).compareTo(b.isNoteOff ? 0 : 1);
      if (byOff != 0) {
        return byOff;
      }
      var byTrack = a.track.compareTo(b.track);
      return byTrack != 0 ? byTrack : a.order.compareTo(b.order);
    });

    var notes = <MidiSongNote>[];
    var messages = <MidiSongMessage>[];
    var texts = <MidiSongText>[];
    var tempos = <MidiTempo>[];
    var timeSignatures = <MidiTimeSignature>[];
    var keySignatures = <MidiKeySignature>[];
    // The notes sounding, by channel and key, first on first off.
    var open = <int, List<_Event>>{};
    void close(_Event on, int tick) {
      var event = on.event as NoteOnEvent;
      notes.add(
        MidiSongNote(
          tick: on.tick,
          ticks: tick - on.tick,
          key: event.note,
          velocity: event.velocity,
          channel: event.channel,
          fileTrack: on.track,
        ),
      );
    }

    for (var item in events) {
      var event = item.event;
      if (event is NoteOnEvent && event.velocity > 0) {
        open.putIfAbsent(event.channel * 128 + event.note, () => []).add(item);
      } else if (event is NoteOnEvent || event is NoteOffEvent) {
        var noteEvent = event as NoteEvent;
        var sounding = open[noteEvent.channel * 128 + noteEvent.note];
        if (sounding != null && sounding.isNotEmpty) {
          close(sounding.removeAt(0), item.tick);
        }
      } else if (event is ChannelEvent) {
        var message = _message(item);
        if (message != null) {
          messages.add(message);
        }
      } else if (event is MetaEvent) {
        var data = event.data;
        switch (event.metaCommand) {
          case MetaEvent.metaTempo when data.length >= 3:
            tempos.add(
              MidiTempo(item.tick, (data[0] << 16) | (data[1] << 8) | data[2]),
            );
          case MetaEvent.metaTimeSig when data.length >= 2:
            timeSignatures.add(
              MidiTimeSignature(item.tick, data[0], 1 << data[1]),
            );
          case MetaEvent.metaKeySig when data.length >= 2:
            var alterations = data[0] > 127 ? data[0] - 256 : data[0];
            keySignatures.add(
              MidiKeySignature(item.tick, alterations, minor: data[1] == 1),
            );
          case var type when type >= 0x01 && type <= 0x0f:
            texts.add(
              MidiSongText(
                tick: item.tick,
                type: type,
                bytes: List.unmodifiable(data),
                fileTrack: item.track,
              ),
            );
        }
      }
    }
    // A note never released ends with the song.
    for (var sounding in open.values) {
      for (var on in sounding) {
        close(on, lengthTicks);
      }
    }
    notes.sort((a, b) => a.tick.compareTo(b.tick));

    var ppq = file.ppq;
    var tempoMap = ppq != null
        ? MidiTempoMap(ppq: ppq, tempos: tempos)
        : MidiTempoMap.smpte(
            (file.frameCountPerSecond! * file.divisionCountPerFrame!)
                .toDouble(),
          );
    if (timeSignatures.isEmpty || timeSignatures.first.tick > 0) {
      timeSignatures.insert(0, const MidiTimeSignature(0, 4, 4));
    }
    return MidiSong._(
      format: file.fileFormat,
      tempoMap: tempoMap,
      notes: List.unmodifiable(notes),
      messages: List.unmodifiable(messages),
      texts: List.unmodifiable(texts),
      timeSignatures: List.unmodifiable(timeSignatures),
      keySignatures: List.unmodifiable(keySignatures),
      fileTrackCount: file.trackCount,
      lengthTicks: lengthTicks,
    );
  }

  static MidiSongMessage? _message(_Event item) {
    var event = item.event;
    int status(int type) => (type << 4) | (event as ChannelEvent).channel;
    MidiSongMessage message(int type, int data1, [int data2 = 0]) =>
        MidiSongMessage(
          tick: item.tick,
          status: status(type),
          data1: data1,
          data2: data2,
          fileTrack: item.track,
        );
    return switch (event) {
      ControlChangeEvent() => message(
        MidiEvent.controlChange,
        event.controller,
        event.value,
      ),
      ProgramChangeEvent() => message(MidiEvent.programChange, event.program),
      PitchWheelChangeEvent() => message(
        MidiEvent.pitchWheelChange,
        event.bottom,
        event.top,
      ),
      KeyAfterTouchEvent() => message(
        MidiEvent.keyAfterTouch,
        event.note,
        event.velocity,
      ),
      ChannelAfterTouchEvent() => message(
        MidiEvent.channelAfterTouch,
        event.amount,
      ),
      _ => null,
    };
  }

  /// The seconds of [tick], at speed 1.
  double secondsOf(num tick) => tempoMap.secondsOf(tick);

  /// The tick at [seconds], with its fraction.
  double tickAt(double seconds) => tempoMap.tickAt(seconds);

  /// The length, in seconds.
  double get duration => secondsOf(lengthTicks);

  /// The ticks of a quarter note (with an SMPTE division, those of half a
  /// second, as at 120 bpm).
  double get _ticksPerQuarter =>
      tempoMap.ppq?.toDouble() ?? tempoMap.ticksPerSecond! / 2;

  /// The names of the tracks of the file, null when a track has none.
  List<String?> get trackNames {
    var names = List<String?>.filled(fileTrackCount, null);
    for (var text in texts) {
      if (text.type == MidiSongText.trackName &&
          names[text.fileTrack] == null) {
        names[text.fileTrack] = text.value;
      }
    }
    return names;
  }

  /// The lyric events (RP-017).
  Iterable<MidiSongText> get lyrics =>
      texts.where((text) => text.type == MidiSongText.lyric);

  /// The markers.
  Iterable<MidiSongText> get markers =>
      texts.where((text) => text.type == MidiSongText.marker);

  /// The copyright notice, null when none.
  String? get copyright => texts
      .where((text) => text.type == MidiSongText.copyright)
      .firstOrNull
      ?.value;

  /// The channels that play notes, in order.
  List<int> get channels =>
      {for (var note in notes) note.channel}.toList()..sort();

  /// The program of each channel at its first note (0 when none was set).
  Map<int, int> get initialPrograms {
    var firstNotes = <int, int>{};
    for (var note in notes) {
      firstNotes.putIfAbsent(note.channel, () => note.tick);
    }
    var programs = {for (var channel in firstNotes.keys) channel: 0};
    for (var message in messages) {
      var channel = message.channel;
      if ((message.status & 0xf0) == midiProgramChange &&
          programs.containsKey(channel) &&
          message.tick <= firstNotes[channel]!) {
        programs[channel] = message.data1;
      }
    }
    return programs;
  }

  /// The bars before each time signature, and its ticks per bar and beat.
  List<(MidiTimeSignature, int, double, double)> get _bars {
    var bars = <(MidiTimeSignature, int, double, double)>[];
    var bar = 0;
    for (var signature in timeSignatures) {
      if (bars.isNotEmpty) {
        var (previous, previousBar, ticksPerBar, _) = bars.last;
        bar =
            previousBar +
            ((signature.tick - previous.tick) / ticksPerBar - 1e-9).ceil();
      }
      var ticksPerBeat = _ticksPerQuarter * 4 / signature.bottom;
      bars.add((signature, bar, ticksPerBeat * signature.top, ticksPerBeat));
    }
    return bars;
  }

  /// The bar and beat at [tick].
  MidiBarBeat barBeatAt(num tick) {
    var bars = _bars;
    var index = bars.lastIndexWhere((entry) => entry.$1.tick <= tick);
    var (signature, bar, ticksPerBar, ticksPerBeat) = bars[math.max(0, index)];
    var into = tick - signature.tick;
    var bars0 = (into / ticksPerBar).floor();
    var inBar = into - bars0 * ticksPerBar;
    var beat = (inBar / ticksPerBeat).floor();
    return MidiBarBeat(bar + bars0, beat, inBar / ticksPerBeat - beat);
  }

  /// The tick of [beat] of [bar] (counted from 0).
  double tickOf(int bar, [int beat = 0]) {
    var bars = _bars;
    var index = bars.lastIndexWhere((entry) => entry.$2 <= bar);
    var (signature, firstBar, ticksPerBar, ticksPerBeat) =
        bars[math.max(0, index)];
    return signature.tick +
        (bar - firstBar) * ticksPerBar +
        beat * ticksPerBeat;
  }

  /// The timeline of the song, at speed 1.
  ///
  /// [trackOf] gives the engine track (its synth) of each note and message,
  /// track 0 by default. [programs] overrides the program of channels: their
  /// own program changes are dropped.
  MidiTimeline toTimeline({
    int Function(int fileTrack, int channel)? trackOf,
    Map<int, int> programs = const {},
  }) {
    int track(int fileTrack, int channel) =>
        trackOf?.call(fileTrack, channel) ?? 0;
    var timelineMessages = <MidiTimelineMessage>[
      for (var MapEntry(key: channel, value: program) in programs.entries)
        MidiTimelineMessage(
          time: 0,
          status: midiProgramChange | channel,
          data1: program,
          track: track(0, channel),
        ),
      for (var message in messages)
        if ((message.status & 0xf0) != midiProgramChange ||
            !programs.containsKey(message.channel))
          MidiTimelineMessage(
            time: secondsOf(message.tick),
            status: message.status,
            data1: message.data1,
            data2: message.data2,
            track: track(message.fileTrack, message.channel),
          ),
    ];
    return MidiTimeline(
      notes: [
        for (var note in notes)
          MidiTimelineNote(
            start: secondsOf(note.tick),
            duration: secondsOf(note.endTick) - secondsOf(note.tick),
            key: note.key,
            velocity: note.velocity,
            track: track(note.fileTrack, note.channel),
            channel: note.channel,
          ),
      ],
      messages: timelineMessages,
      start: 0,
      end: duration,
    );
  }
}

/// An event of a track at its absolute tick.
class _Event {
  final int tick;
  final int track;
  final int order;
  final MidiEvent event;

  _Event(this.tick, this.track, this.order, this.event);

  bool get isNoteOff {
    var event = this.event;
    return event is NoteOffEvent ||
        (event is NoteOnEvent && event.velocity == 0);
  }
}

/// The characters of Windows-1252 from 0x80 to 0x9F (the bytes it leaves
/// undefined are kept as their code).
const _cp1252 = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

/// The text of [bytes]: UTF-8, or Windows-1252 when they are not UTF-8 (the
/// encoding of most `.kar` files).
String midiDecodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes([
      for (var byte in bytes)
        if (byte >= 0x80 && byte < 0xA0) _cp1252[byte - 0x80] else byte & 0xFF,
    ]);
  }
}
