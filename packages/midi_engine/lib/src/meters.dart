/// The meters of the tracks, reported by an engine host with its position
/// events: the peak of each track, the keys sounding on each (a mixer, a
/// keyboard view). As typed lists in the events, small.
library;

import 'dart:typed_data';

/// What the tracks play: their peak level and their keys sounding.
class MidiTrackMeters {
  /// The peak level of each track over the frames since the previous
  /// meters, after its volume (a muted track is at 0), before the pan, the
  /// master gain and the limiter: 1 is full scale.
  final List<double> levels;

  /// The keys sounding on each track: the notes started and not released
  /// yet (their release tails are not counted), transposed (the keys
  /// heard).
  final List<Set<int>> keys;

  /// Meters of [levels] and [keys] (one per track each).
  MidiTrackMeters({required List<double> levels, required List<Set<int>> keys})
    : levels = List.unmodifiable(levels),
      keys = List.unmodifiable([
        for (var set in keys) Set<int>.unmodifiable(set),
      ]);

  /// Silence on [trackCount] tracks.
  factory MidiTrackMeters.silent(int trackCount) => MidiTrackMeters(
    levels: Float32List(trackCount),
    keys: [for (var i = 0; i < trackCount; i++) const <int>{}],
  );

  /// The number of tracks.
  int get trackCount => levels.length;

  /// True when no track sounds.
  bool get isSilent =>
      levels.every((level) => level == 0) && keys.every((set) => set.isEmpty);

  /// The meters of an event with them ([midiMetersEventFields]), on
  /// [trackCount] tracks; null when it has none.
  static MidiTrackMeters? fromEvent(
    Map<Object?, Object?> event,
    int trackCount,
  ) {
    var levels = event['levels'];
    if (levels is! List) {
      return null;
    }
    // A Float32List made here: dart2js then knows the typed arrays received.
    var values = Float32List(trackCount);
    for (var i = 0; i < trackCount && i < levels.length; i++) {
      values[i] = (levels[i] as num).toDouble();
    }
    var sets = [for (var i = 0; i < trackCount; i++) <int>{}];
    var keys = event['keys'];
    if (keys is List) {
      for (var value in keys) {
        var encoded = (value as num).toInt();
        var track = encoded >> 7;
        if (track < trackCount) {
          sets[track].add(encoded & 0x7f);
        }
      }
    }
    return MidiTrackMeters(levels: values, keys: sets);
  }

  @override
  String toString() => 'MidiTrackMeters($levels, $keys)';
}

/// The fields of the meters in an event: `levels`, a Float32List of the
/// peak of each track, and `keys`, an Int32List of `track * 128 + key` for
/// each note sounding.
Map<String, Object?> midiMetersEventFields(
  Float32List levels,
  List<({int track, int channel, int key})> sounding,
) => {
  'levels': levels,
  'keys': Int32List.fromList([
    for (var note in sounding) note.track * 128 + note.key,
  ]),
};
