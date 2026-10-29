/// Chord symbols (`C`, `Am7`, `G7`, `Fmaj7`, `Bb`, `F#m7b5`...) and their
/// voicings.
library;

const _names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

const _qualities = <String, List<int>>{
  '': [0, 4, 7],
  'm': [0, 3, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'm7b5': [0, 3, 6, 10],
  'dim': [0, 3, 6],
  'dim7': [0, 3, 6, 9],
  'aug': [0, 4, 8],
  'sus4': [0, 5, 7],
  '6': [0, 4, 7, 9],
  'm6': [0, 3, 7, 9],
  '9': [0, 4, 7, 10, 14],
  'm9': [0, 3, 7, 10, 14],
  '5': [0, 7],
};

/// A chord: its root (a pitch class, 0 for C) and its intervals.
class MidiChord {
  /// The symbol.
  final String symbol;

  /// The pitch class of the root, 0 (C) to 11 (B).
  final int root;

  /// The intervals above the root, in semitones.
  final List<int> intervals;

  MidiChord._(this.symbol, this.root, this.intervals);

  /// The chord of [symbol] (`C`, `Am7`, `G7`, `Fmaj7`, `Bb`, `F#m7b5`...).
  factory MidiChord.parse(String symbol) {
    var root = _names[symbol[0]];
    if (root == null) {
      throw FormatException('not a chord: $symbol');
    }
    var rest = symbol.substring(1);
    if (rest.startsWith('#')) {
      root++;
      rest = rest.substring(1);
    } else if (rest.startsWith('b')) {
      root--;
      rest = rest.substring(1);
    }
    var intervals = _qualities[rest];
    if (intervals == null) {
      throw FormatException('not a chord: $symbol');
    }
    return MidiChord._(symbol, root % 12, intervals);
  }

  /// True for a minor third.
  bool get isMinor => intervals.length > 1 && intervals[1] == 3;

  /// The key of the root in the octave starting at [low] (36: C2 to B2).
  int bass([int low = 36]) => low + (root - low) % 12;

  /// The key of [interval] above the bass of [low].
  int bassInterval(int interval, [int low = 36]) => bass(low) + interval;

  /// The pitch classes.
  List<int> get pitchClasses => [
    for (var interval in intervals) (root + interval) % 12,
  ];

  /// A closed voicing of [count] notes (all the notes by default) from the
  /// first chord tone at or above [low].
  List<int> voicing(int low, {int? count}) {
    var classes = pitchClasses;
    var notes = <int>[];
    var key = low;
    while (notes.length < (count ?? classes.length)) {
      if (classes.contains(key % 12)) {
        notes.add(key);
      }
      key++;
    }
    return notes;
  }

  /// The chord tones from [low] to [high].
  List<int> tones(int low, int high) => [
    for (var key = low; key <= high; key++)
      if (pitchClasses.contains(key % 12)) key,
  ];

  @override
  String toString() => symbol;
}
