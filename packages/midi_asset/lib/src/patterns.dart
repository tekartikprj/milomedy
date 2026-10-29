/// The patterns of the styles: drums, bass lines, comping, melodies, over a
/// chord progression.
library;

import 'builder.dart';
import 'chord.dart';
import 'random.dart';

/// The General MIDI drum keys used.
abstract final class MidiDrum {
  /// Bass drum.
  static const kick = 36;

  /// Side stick (rim shot).
  static const sideStick = 37;

  /// Snare drum.
  static const snare = 38;

  /// Hand clap.
  static const clap = 39;

  /// Closed hi-hat.
  static const closedHat = 42;

  /// Pedal hi-hat.
  static const pedalHat = 44;

  /// Low tom.
  static const lowTom = 45;

  /// Open hi-hat.
  static const openHat = 46;

  /// Middle tom.
  static const midTom = 47;

  /// Crash cymbal.
  static const crash = 49;

  /// High tom.
  static const highTom = 50;

  /// Ride cymbal.
  static const ride = 51;

  /// Tambourine.
  static const tambourine = 54;

  /// Cowbell.
  static const cowbell = 56;

  /// Muted high conga.
  static const muteConga = 62;

  /// Open high conga.
  static const openConga = 63;

  /// Low conga.
  static const lowConga = 64;

  /// High timbale.
  static const highTimbale = 65;

  /// Cabasa.
  static const cabasa = 69;

  /// Maracas.
  static const maracas = 70;

  /// Claves.
  static const claves = 75;
}

/// The chords of bars: one symbol per bar, or two (`"C G"`, half a bar
/// each).
class MidiAssetProgression {
  /// The symbols, by bar.
  final List<String> bars;

  /// A progression.
  const MidiAssetProgression(this.bars);

  /// Its chords from bar [fromBar] of [song]: their start, their length (in
  /// beats), the chord; [count] bars (its length by default), repeated.
  List<(double, double, MidiChord)> chords(
    MidiAssetSongBuilder song,
    int fromBar, {
    int? count,
  }) {
    var result = <(double, double, MidiChord)>[];
    var bars = count ?? this.bars.length;
    for (var i = 0; i < bars; i++) {
      var symbols = this.bars[i % this.bars.length].split(' ');
      var start = song.bar(fromBar + i);
      var beats = song.beatsPerBar / symbols.length;
      for (var (j, symbol) in symbols.indexed) {
        result.add((start + j * beats, beats, MidiChord.parse(symbol)));
      }
    }
    return result;
  }
}

/// Plays [pattern] on [part] for [bars] bars from [fromBar]: each drum key
/// with a string of the steps of a bar (`X` accent, `x` hit, `o` ghost, `.`
/// rest). [swing] (0 to 0.33) delays the second step of each pair.
void midiAssetDrums(
  MidiAssetSongBuilder song,
  MidiAssetPart part,
  Map<int, String> pattern, {
  required int fromBar,
  required int bars,
  double swing = 0,
  MidiAssetRandom? random,
}) {
  for (var bar = fromBar; bar < fromBar + bars; bar++) {
    for (var MapEntry(key: key, value: steps) in pattern.entries) {
      var step = song.beatsPerBar / steps.length;
      for (var i = 0; i < steps.length; i++) {
        var velocity = switch (steps[i]) {
          'X' => 115,
          'x' => 90,
          'o' => 50,
          _ => 0,
        };
        if (velocity == 0) {
          continue;
        }
        var shift = i.isOdd ? swing * step : 0.0;
        var humanize = random == null ? 0 : random.nextInt(13) - 6;
        part.note(
          song.bar(bar) + i * step + shift,
          step * 0.9,
          key,
          velocity + humanize,
        );
      }
    }
  }
}

/// A crash and a kick on the first beat of [bar].
void midiAssetCrash(MidiAssetSongBuilder song, MidiAssetPart drums, int bar) {
  drums
    ..note(song.bar(bar), 2, MidiDrum.crash, 110)
    ..note(song.bar(bar), 1, MidiDrum.kick, 110);
}

/// The bass line styles.
enum MidiAssetBass {
  /// The root on each beat.
  roots,

  /// The root in eighths.
  eighths,

  /// The root on beat 1, the fifth on beat 3 (country, march, polka).
  rootFifth,

  /// A walking line: four chord tones a bar, an approach to the next root.
  walking,

  /// Octaves in eighths (disco).
  octaves,

  /// Syncopated sixteenths, octaves and ghosts (funk).
  funk,

  /// The one drop: the root late on beat 1, then the fifth (reggae).
  reggae,

  /// The tumbao: the and of 2 and beat 4, anticipating (salsa).
  tumbao,

  /// The root and the fifth of the bossa nova.
  bossa,

  /// The boogie-woogie walk: root, third, fifth, sixth, seventh in eighths.
  boogie,

  /// The root on the first beat, held (a waltz, a ballad).
  downbeat,
}

/// Plays the bass [style] over [progression] on [part] from [fromBar] for
/// [bars] bars (the progression repeated), the root in the octave from
/// [low].
void midiAssetBass(
  MidiAssetSongBuilder song,
  MidiAssetPart part,
  MidiAssetProgression progression,
  MidiAssetBass style, {
  required int fromBar,
  int? bars,
  int low = 36,
  double swing = 0,
  MidiAssetRandom? random,
}) {
  var chords = progression.chords(song, fromBar, count: bars);
  for (var (index, (start, beats, chord)) in chords.indexed) {
    var root = chord.bass(low);
    var fifth = root + 7;
    var next = index + 1 < chords.length ? chords[index + 1].$3 : chord;
    int velocity(int base) =>
        base + (random == null ? 0 : random.nextInt(11) - 5);
    void play(double at, double length, int key, [int base = 95]) {
      if (at < beats) {
        part.note(start + at, length, key, velocity(base));
      }
    }

    switch (style) {
      case MidiAssetBass.roots:
        for (var beat = 0; beat < beats; beat++) {
          play(beat.toDouble(), 0.9, root);
        }
      case MidiAssetBass.eighths:
        for (var i = 0; i < beats * 2; i++) {
          play(
            i / 2 + (i.isOdd ? swing / 2 : 0),
            0.45,
            root,
            i.isEven ? 100 : 85,
          );
        }
      case MidiAssetBass.rootFifth:
        for (var beat = 0; beat < beats; beat += 2) {
          play(beat.toDouble(), 0.9, beat % 4 == 0 ? root : fifth - 12);
        }
      case MidiAssetBass.walking:
        var target = next.bass(low);
        var walk = [
          root,
          chord.tones(root + 1, root + 9).first,
          fifth,
          // An approach a semitone below or above the next root.
          target + ((random?.chance(0.5) ?? true) ? -1 : 1),
        ];
        for (var beat = 0; beat < beats && beat < 4; beat++) {
          play(beat.toDouble(), 0.9, walk[beat], beat == 0 ? 100 : 88);
        }
      case MidiAssetBass.octaves:
        for (var i = 0; i < beats * 2; i++) {
          play(i / 2, 0.4, i.isEven ? root : root + 12, i.isEven ? 100 : 90);
        }
      case MidiAssetBass.funk:
        const steps = 'X..x.oX.x.X..ox.';
        for (var i = 0; i < steps.length && i / 4 < beats; i++) {
          var key = switch (i % 5) {
            2 => root + 12,
            4 => root + chord.intervals.last,
            _ => root,
          };
          switch (steps[i]) {
            case 'X':
              play(i / 4, 0.22, root, 110);
            case 'x':
              play(i / 4, 0.2, key, 92);
            case 'o':
              play(i / 4, 0.1, key, 55);
          }
        }
      case MidiAssetBass.reggae:
        play(0.5, 1.4, root, 105);
        play(2, 0.4, root, 90);
        play(2.5, 0.9, fifth, 90);
      case MidiAssetBass.tumbao:
        // The root of the next chord, anticipated.
        play(1.5, 1.4, fifth, 95);
        play(3, 0.9, next.bass(low), 100);
      case MidiAssetBass.bossa:
        for (var beat = 0; beat < beats; beat += 2) {
          play(beat.toDouble(), 1.4, root, 95);
          play(beat + 1.5, 0.45, fifth - 12, 85);
        }
      case MidiAssetBass.boogie:
        var seventh = chord.intervals.contains(10) ? 10 : 9;
        var walk = [0, 4, 7, 9, seventh, 9, 7, 4];
        for (var i = 0; i < beats * 2; i++) {
          play(
            i / 2 + (i.isOdd ? swing / 2 : 0),
            0.45,
            root + walk[i % walk.length],
            i.isEven ? 100 : 85,
          );
        }
      case MidiAssetBass.downbeat:
        play(0, beats * 0.9, root);
    }
  }
}

/// The comping styles.
enum MidiAssetComp {
  /// The chord held (an organ, strings, a pad).
  pad,

  /// The chord on each beat (piano pop).
  block,

  /// Short chords off the beat (funk brass, clavinet).
  stabs,

  /// Short chords on the and of each beat (reggae, the organ bubble).
  skank,

  /// Power chords in eighths (rock guitar).
  power,

  /// The chord tones up and down in eighths.
  arpeggio,

  /// The chord tones up and down in sixteenths.
  arpeggio16,

  /// The salsa montuno: octave chord tones in syncopated eighths.
  montuno,

  /// The chord on beats 2 and 3 (a waltz, the bass playing beat 1).
  waltz,

  /// Stride: a bass note on 1 and 3, the chord on 2 and 4 (ragtime).
  stride,

  /// The third and seventh on the Charleston rhythm (jazz).
  shells,

  /// The bossa nova guitar: the chord on syncopated eighths.
  bossa,

  /// The guitar strummed, down and up in eighths.
  strum,
}

/// Plays the comping [style] over [progression] on [part] from [fromBar]
/// for [bars] bars, the voicings from [low].
void midiAssetComp(
  MidiAssetSongBuilder song,
  MidiAssetPart part,
  MidiAssetProgression progression,
  MidiAssetComp style, {
  required int fromBar,
  int? bars,
  int low = 55,
  double swing = 0,
  int velocity = 75,
  MidiAssetRandom? random,
}) {
  var chords = progression.chords(song, fromBar, count: bars);
  for (var (start, beats, chord) in chords) {
    var voicing = chord.voicing(low, count: 4);
    int vel(int delta) =>
        velocity + delta + (random == null ? 0 : random.nextInt(9) - 4);
    void play(double at, double length, List<int> keys, [int delta = 0]) {
      if (at < beats) {
        part.chord(start + at, length, keys, vel(delta));
      }
    }

    switch (style) {
      case MidiAssetComp.pad:
        play(0, beats * 0.98, voicing);
      case MidiAssetComp.block:
        for (var beat = 0; beat < beats; beat++) {
          play(beat.toDouble(), 0.9, voicing, beat == 0 ? 8 : 0);
        }
      case MidiAssetComp.stabs:
        for (var at in const [0.0, 1.5, 2.75]) {
          play(at, 0.2, voicing, at == 0 ? 10 : 0);
        }
      case MidiAssetComp.skank:
        for (var beat = 0; beat < beats; beat++) {
          play(beat + 0.5, 0.2, voicing);
        }
      case MidiAssetComp.power:
        var root = chord.bass(40);
        for (var i = 0; i < beats * 2; i++) {
          play(i / 2, 0.45, [root, root + 7, root + 12], i.isEven ? 8 : 0);
        }
      case MidiAssetComp.arpeggio:
      case MidiAssetComp.arpeggio16:
        var per = style == MidiAssetComp.arpeggio ? 2 : 4;
        var tones = chord.tones(low, low + 14);
        var pattern = [
          ...tones,
          ...tones.reversed.skip(1).take(tones.length - 2),
        ];
        for (var i = 0; i < beats * per; i++) {
          var at = i / per + (i.isOdd ? swing / per : 0);
          play(at, 1.5 / per, [
            pattern[i % pattern.length],
          ], i % per == 0 ? 6 : -4);
        }
      case MidiAssetComp.montuno:
        var tones = chord.tones(low, low + 12);
        const steps = [0.0, 0.5, 1.5, 2.0, 2.5, 3.5];
        for (var (i, at) in steps.indexed) {
          var key = tones[i % tones.length];
          play(at, 0.4, [key, key + 12]);
        }
      case MidiAssetComp.waltz:
        for (var beat = 1; beat < beats; beat++) {
          play(beat.toDouble(), 0.6, voicing.take(3).toList(), -6);
        }
      case MidiAssetComp.stride:
        var root = chord.bass(36);
        for (var beat = 0; beat < beats; beat++) {
          if (beat.isEven) {
            play(beat.toDouble(), 0.8, [
              if (beat % 4 == 0) root else root + 7,
            ], 10);
          } else {
            play(beat.toDouble(), 0.6, chord.voicing(52, count: 3));
          }
        }
      case MidiAssetComp.shells:
        var third = chord.bass(low - 12) + chord.intervals[1] + 12;
        var seventh = chord.bass(low - 12) + chord.intervals.last + 12;
        play(0, 0.9, [third, seventh]);
        play(1.5 + swing / 2, 0.4, [third, seventh], -8);
      case MidiAssetComp.bossa:
        for (var at in const [0.0, 1.0, 1.5, 2.5, 3.0]) {
          play(at, 0.4, voicing, at == 0 ? 6 : 0);
        }
      case MidiAssetComp.strum:
        for (var i = 0; i < beats * 2; i++) {
          // Up strokes softer, the voicing from the top.
          var keys = i.isEven ? voicing : voicing.reversed.toList();
          play(i / 2, 0.45, keys, i.isEven ? 4 : -12);
        }
    }
  }
}

/// The scale of [tonic] (a pitch class), major or [minor] (natural).
List<int> midiAssetScale(int tonic, {bool minor = false}) => [
  for (var step
      in minor ? const [0, 2, 3, 5, 7, 8, 10] : const [0, 2, 4, 5, 7, 9, 11])
    (tonic + step) % 12,
];

/// Plays a melody on [part] over [progression] from [fromBar] for [bars]
/// bars, between [low] and [high]: phrases of two bars whose rhythms come
/// from [rhythms] (the start and the length of each note in a bar), the
/// first phrase repeated in the third, chord tones on the strong beats,
/// scale steps between, the root at the end.
void midiAssetMelody(
  MidiAssetSongBuilder song,
  MidiAssetPart part,
  MidiAssetProgression progression, {
  required int fromBar,
  required int bars,
  required List<int> scale,
  required List<List<(double, double)>> rhythms,
  required MidiAssetRandom random,
  int low = 60,
  int high = 79,
  double swing = 0,
  int velocity = 95,
}) {
  var chords = progression.chords(song, fromBar, count: bars);
  MidiChord chordAt(double beat) {
    var chord = chords.first.$3;
    for (var (start, _, c) in chords) {
      if (start <= beat) {
        chord = c;
      }
    }
    return chord;
  }

  var phrase = <List<(double, double)>>[];
  var key = (low + high) ~/ 2;
  for (var bar = 0; bar < bars; bar++) {
    var inPhrase = bar % 8;
    List<(double, double)> rhythm;
    if (bar == bars - 1) {
      // The end: a long note.
      rhythm = [(0, song.beatsPerBar - 0.1)];
    } else if (inPhrase >= 4 && inPhrase < 6 && phrase.length > inPhrase - 4) {
      rhythm = phrase[inPhrase - 4];
    } else {
      rhythm = random.pick(rhythms);
      if (inPhrase < 2) {
        phrase.add(rhythm);
      }
    }
    for (var (at, length) in rhythm) {
      var beat = song.bar(fromBar + bar) + at;
      var chord = chordAt(beat);
      var strong = at == at.roundToDouble() && at.round().isEven;
      if (bar == bars - 1) {
        // The root of the last chord.
        key = chord
            .tones(low, high)
            .where((k) => k % 12 == chord.root)
            .fold(
              key,
              (best, k) => (k - key).abs() < (best - key).abs() ? k : best,
            );
      } else if (strong) {
        var tones = chord.tones(low, high);
        tones.sort((a, b) => (a - key).abs().compareTo((b - key).abs()));
        key = tones[random.nextInt(tones.length < 3 ? tones.length : 3)];
      } else {
        var step = random.pick(const [-2, -1, -1, 1, 1, 2]);
        var candidate = key;
        var moved = 0;
        while (moved != step.abs()) {
          candidate += step.sign;
          if (scale.contains(candidate % 12)) {
            moved++;
          }
        }
        if (candidate < low || candidate > high) {
          candidate = key - (candidate - key);
        }
        key = candidate.clamp(low, high);
      }
      var shift = at - at.floor() == 0.5 ? swing / 2 : 0.0;
      part.note(
        beat + shift,
        length * 0.92,
        key,
        velocity + (strong ? 8 : 0) + random.nextInt(9) - 4,
      );
    }
  }
}

/// Rhythms of a bar of four beats for the melodies.
const midiAssetRhythms4 = <List<(double, double)>>[
  [(0, 1), (1, 1), (2, 1.5), (3.5, 0.5)],
  [(0, 1.5), (1.5, 0.5), (2, 2)],
  [(0, 0.5), (0.5, 0.5), (1, 1), (2, 1), (3, 1)],
  [(0, 2), (2, 1), (3, 1)],
  [(0.5, 0.5), (1, 1), (2, 0.5), (2.5, 1.5)],
  [(0, 1), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 1)],
];

/// Rhythms of a bar of three beats.
const midiAssetRhythms3 = <List<(double, double)>>[
  [(0, 2), (2, 1)],
  [(0, 1), (1, 1), (2, 1)],
  [(0, 1.5), (1.5, 0.5), (2, 1)],
  [(0, 3)],
];

/// Busy rhythms of four beats (bebop, funk, salsa).
const midiAssetRhythmsBusy = <List<(double, double)>>[
  [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 1), (3, 0.5), (3.5, 0.5)],
  [(0.5, 0.5), (1, 0.5), (1.5, 0.5), (2.5, 0.5), (3, 1)],
  [(0, 0.5), (0.5, 1), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 1)],
  [(0, 1), (1, 0.5), (1.5, 0.5), (2, 0.5), (2.5, 1.5)],
];
