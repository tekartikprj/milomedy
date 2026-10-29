/// The timeline the engine plays: notes and channel messages in seconds, on
/// tracks. A MIDI file, a score, a sequencer project or a generated pattern
/// each build one.
library;

/// A note: on at [start], off [duration] later.
class MidiTimelineNote {
  /// The start, in seconds (negative in a count-in).
  final double start;

  /// The length, in seconds.
  final double duration;

  /// The track (its synth).
  final int track;

  /// The MIDI channel, 0 to 15.
  final int channel;

  /// The key, 0 to 127.
  final int key;

  /// The velocity, 1 to 127.
  final int velocity;

  /// A note.
  const MidiTimelineNote({
    required this.start,
    required this.duration,
    required this.key,
    this.velocity = 100,
    this.track = 0,
    this.channel = 0,
  });

  /// The end, in seconds.
  double get end => start + duration;

  @override
  String toString() =>
      'MidiTimelineNote(${start.toStringAsFixed(3)}, '
      '${duration.toStringAsFixed(3)}, $key, track $track, channel $channel)';
}

/// A channel message other than the notes: a controller, a program, a pitch
/// bend. Played again by a seek, up to the place sought.
class MidiTimelineMessage {
  /// The time, in seconds.
  final double time;

  /// The track (its synth).
  final int track;

  /// The status, its channel in the low 4 bits.
  final int status;

  /// The first data byte.
  final int data1;

  /// The second data byte.
  final int data2;

  /// A message.
  const MidiTimelineMessage({
    required this.time,
    required this.status,
    required this.data1,
    this.data2 = 0,
    this.track = 0,
  });

  /// The channel.
  int get channel => status & 0x0f;

  @override
  String toString() =>
      'MidiTimelineMessage(${time.toStringAsFixed(3)}, '
      '0x${status.toRadixString(16)}, $data1, $data2, track $track)';
}

/// What the engine plays: notes and messages, sorted by time.
class MidiTimeline {
  /// The notes, by start.
  final List<MidiTimelineNote> notes;

  /// The messages, by time.
  final List<MidiTimelineMessage> messages;

  /// Where playing starts, in seconds (negative with a count-in).
  final double start;

  /// Where playing ends, in seconds.
  final double end;

  MidiTimeline._(this.notes, this.messages, this.start, this.end);

  /// A timeline of [notes] and [messages] (sorted here, in a stable way),
  /// from [start] (0, or the first event when earlier) to [end] (the last
  /// note end or message by default).
  factory MidiTimeline({
    Iterable<MidiTimelineNote> notes = const [],
    Iterable<MidiTimelineMessage> messages = const [],
    double? start,
    double? end,
  }) {
    var sortedNotes = _sorted(notes, (note) => note.start);
    var sortedMessages = _sorted(messages, (message) => message.time);
    var first = 0.0;
    var last = 0.0;
    for (var note in sortedNotes) {
      if (note.start < first) {
        first = note.start;
      }
      if (note.end > last) {
        last = note.end;
      }
    }
    if (sortedMessages.isNotEmpty) {
      if (sortedMessages.first.time < first) {
        first = sortedMessages.first.time;
      }
      if (sortedMessages.last.time > last) {
        last = sortedMessages.last.time;
      }
    }
    return MidiTimeline._(
      List.unmodifiable(sortedNotes),
      List.unmodifiable(sortedMessages),
      start ?? first,
      end ?? last,
    );
  }

  /// The tracks used: one more than the highest.
  int get trackCount {
    var count = 0;
    for (var note in notes) {
      if (note.track >= count) {
        count = note.track + 1;
      }
    }
    for (var message in messages) {
      if (message.track >= count) {
        count = message.track + 1;
      }
    }
    return count;
  }

  /// The length played, in seconds.
  double get duration => end - start;
}

/// [items] sorted by [time], equal times kept in their order.
List<T> _sorted<T>(Iterable<T> items, double Function(T item) time) {
  var indexed = items.indexed.toList();
  indexed.sort((a, b) {
    var byTime = time(a.$2).compareTo(time(b.$2));
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (var (_, item) in indexed) item];
}
