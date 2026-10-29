/// The songs: fifteen for a band, five for the piano alone.
library;

import 'builder.dart';
import 'chord.dart';
import 'patterns.dart';
import 'random.dart';

// The General MIDI programs used (from 0).
const _piano = 0;
const _electricPiano = 4;
const _clavinet = 7;
const _vibraphone = 11;
const _drawbarOrgan = 16;
const _percussiveOrgan = 17;
const _rockOrgan = 18;
const _accordion = 21;
const _harmonica = 22;
const _nylonGuitar = 24;
const _steelGuitar = 25;
const _cleanGuitar = 27;
const _mutedGuitar = 28;
const _overdrivenGuitar = 29;
const _distortionGuitar = 30;
const _acousticBass = 32;
const _fingerBass = 33;
const _pickBass = 34;
const _slapBass = 36;
const _synthBass = 38;
const _violin = 40;
const _strings = 48;
const _choir = 52;
const _voice = 53;
const _trumpet = 56;
const _trombone = 57;
const _tuba = 58;
const _mutedTrumpet = 59;
const _brass = 61;
const _tenorSax = 66;
const _flute = 73;
const _squareLead = 80;
const _sawLead = 81;
const _warmPad = 89;
const _banjo = 105;
const _fiddle = 110;

/// A comping part of a band song.
typedef _Comp = ({
  String name,
  int program,
  MidiAssetComp style,
  int low,
  int volume,
  int pan,
});

/// A band song: a 2-bar intro (drums and comping), the melody over [a] then
/// over [b] ([a] again by default), a last bar on the tonic chord.
MidiAssetSongBuilder _band({
  required String title,
  required double bpm,
  required int tonic,
  required MidiAssetProgression a,
  MidiAssetProgression? b,
  required Map<int, String> groove,
  required (String, int, MidiAssetBass) bass,
  required List<_Comp> comps,
  required (String, int, int, int) lead,
  required int seed,
  int beatsPerBar = 4,
  bool minor = false,
  int alterations = 0,
  double swing = 0,
  int bassLow = 36,
  List<List<(double, double)>> rhythms = midiAssetRhythms4,
}) {
  var song = MidiAssetSongBuilder(
    title: title,
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    keyAlterations: alterations,
    minor: minor,
  );
  var random = MidiAssetRandom(seed);
  b ??= a;
  var intro = 2;
  var bars = a.bars.length + b.bars.length;
  var end = intro + bars;
  var channel = 0;
  int nextChannel() {
    var next = channel++;
    if (next == midiAssetDrumChannel) {
      next = channel++;
    }
    return next;
  }

  var drums = song.part('Drums', channel: midiAssetDrumChannel, volume: 105);
  midiAssetDrums(
    song,
    drums,
    groove,
    fromBar: 0,
    bars: end,
    swing: swing,
    random: random,
  );
  midiAssetCrash(song, drums, intro);
  midiAssetCrash(song, drums, intro + a.bars.length);
  midiAssetCrash(song, drums, end);

  var (bassName, bassProgram, bassStyle) = bass;
  var bassPart = song.part(
    bassName,
    channel: nextChannel(),
    program: bassProgram,
    volume: 105,
    reverb: 20,
  );
  for (var (from, progression) in [(intro, a), (intro + a.bars.length, b)]) {
    midiAssetBass(
      song,
      bassPart,
      progression,
      bassStyle,
      fromBar: from,
      low: bassLow,
      swing: swing,
      random: random,
    );
  }
  var last = MidiChord.parse(a.bars.last.split(' ').last);
  bassPart.note(song.bar(end), beatsPerBar.toDouble(), last.bass(bassLow), 100);

  for (var comp in comps) {
    var part = song.part(
      comp.name,
      channel: nextChannel(),
      program: comp.program,
      volume: comp.volume,
      pan: comp.pan,
    );
    // The intro on the first chords of a.
    for (var (from, count, progression) in [
      (0, intro, a),
      (intro, a.bars.length, a),
      (intro + a.bars.length, b.bars.length, b),
    ]) {
      midiAssetComp(
        song,
        part,
        progression,
        comp.style,
        fromBar: from,
        bars: count,
        low: comp.low,
        swing: swing,
        random: random,
      );
    }
    part.chord(
      song.bar(end),
      beatsPerBar - 0.1,
      last.voicing(comp.low, count: 4),
      80,
    );
  }

  var (leadName, leadProgram, low, high) = lead;
  var leadPart = song.part(
    leadName,
    channel: nextChannel(),
    program: leadProgram,
    volume: 110,
    pan: 70,
  );
  var scale = midiAssetScale(tonic, minor: minor);
  for (var (from, progression) in [(intro, a), (intro + a.bars.length, b)]) {
    midiAssetMelody(
      song,
      leadPart,
      progression,
      fromBar: from,
      bars: progression.bars.length,
      scale: scale,
      rhythms: rhythms,
      random: random,
      low: low,
      high: high,
      swing: swing,
    );
  }
  return song;
}

_Comp _comp(
  String name,
  int program,
  MidiAssetComp style, {
  int low = 55,
  int volume = 85,
  int pan = 64,
}) => (
  name: name,
  program: program,
  style: style,
  low: low,
  volume: volume,
  pan: pan,
);

/// Rock eighths: kick on 1 and 3, snare on 2 and 4, eighth hats.
const _rockGroove = {
  MidiDrum.kick: 'x.....x.x.......',
  MidiDrum.snare: '....X.......X...',
  MidiDrum.closedHat: 'x.x.x.x.x.x.x.x.',
};

/// Rock in A, 128 bpm: drums, bass, distortion guitar, rock organ, lead guitar.
MidiAssetSongBuilder rockAnthem() => _band(
  title: 'Rock Anthem',
  bpm: 128,
  tonic: 9,
  alterations: 3,
  a: const MidiAssetProgression([
    'A', 'F#m', 'D', 'E', 'A', 'F#m', 'D E', 'A', //
  ]),
  b: const MidiAssetProgression([
    'D', 'E', 'C#m', 'F#m', 'D', 'E', 'D', 'E', //
  ]),
  groove: _rockGroove,
  bass: ('Bass', _pickBass, MidiAssetBass.eighths),
  comps: [
    _comp('Rhythm guitar', _distortionGuitar, MidiAssetComp.power, pan: 30),
    _comp('Organ', _rockOrgan, MidiAssetComp.pad, low: 57, volume: 65, pan: 98),
  ],
  lead: ('Lead guitar', _overdrivenGuitar, 64, 84),
  seed: 1,
);

/// A pop ballad in C, 76 bpm: drums, bass, piano, strings, flute.
MidiAssetSongBuilder popBallad() => _band(
  title: 'Pop Ballad',
  bpm: 76,
  tonic: 0,
  a: const MidiAssetProgression([
    'C', 'G', 'Am', 'F', 'C', 'G', 'F', 'C', //
  ]),
  b: const MidiAssetProgression([
    'Am', 'F', 'C', 'G', 'Am', 'F', 'G', 'C', //
  ]),
  groove: const {
    MidiDrum.kick: 'x.......x.x.....',
    MidiDrum.sideStick: '....x.......x...',
    MidiDrum.closedHat: 'x.o.x.o.x.o.x.o.',
  },
  bass: ('Bass', _fingerBass, MidiAssetBass.rootFifth),
  comps: [
    _comp('Piano', _piano, MidiAssetComp.arpeggio, volume: 90, pan: 50),
    _comp('Strings', _strings, MidiAssetComp.pad, low: 60, volume: 70, pan: 80),
  ],
  lead: ('Flute', _flute, 67, 86),
  seed: 2,
);

/// Funk in E, 104 bpm: drums, slap bass, clavinet, brass, tenor sax.
MidiAssetSongBuilder funkGroove() => _band(
  title: 'Funk Groove',
  bpm: 104,
  tonic: 4,
  alterations: 4,
  a: const MidiAssetProgression([
    'E9', 'E9', 'E9', 'E9', 'A9', 'A9', 'E9', 'B7 A7', //
  ]),
  b: const MidiAssetProgression([
    'A9', 'A9', 'E9', 'E9', 'B7', 'A7', 'E9', 'E9', //
  ]),
  groove: const {
    MidiDrum.kick: 'x..x..x...x..x..',
    MidiDrum.snare: '....X..o.o..X..o',
    MidiDrum.closedHat: 'xxxxxxxxxxxxxxxx',
  },
  bass: ('Slap bass', _slapBass, MidiAssetBass.funk),
  comps: [
    _comp('Clavinet', _clavinet, MidiAssetComp.stabs, low: 60, pan: 40),
    _comp('Brass', _brass, MidiAssetComp.stabs, low: 62, volume: 80, pan: 90),
  ],
  lead: ('Tenor sax', _tenorSax, 58, 77),
  rhythms: midiAssetRhythmsBusy,
  seed: 3,
);

/// The twelve bars of the blues in G.
const _bluesInG = MidiAssetProgression([
  'G7', 'C7', 'G7', 'G7', 'C7', 'C7', //
  'G7', 'G7', 'D7', 'C7', 'G7', 'D7', //
]);

/// A twelve-bar blues shuffle in G, 96 bpm: drums, bass, organ, guitar, harmonica.
MidiAssetSongBuilder bluesShuffle() => _band(
  title: 'Blues Shuffle',
  bpm: 96,
  tonic: 7,
  alterations: 1,
  a: _bluesInG,
  groove: const {
    MidiDrum.kick: 'x.......x.......',
    MidiDrum.snare: '....X.......X...',
    MidiDrum.ride: 'x.x.x.x.x.x.x.x.',
  },
  swing: 0.22,
  bass: ('Bass', _fingerBass, MidiAssetBass.boogie),
  comps: [
    _comp('Organ', _drawbarOrgan, MidiAssetComp.pad, volume: 70, pan: 40),
    _comp('Guitar', _cleanGuitar, MidiAssetComp.shells, low: 60, pan: 90),
  ],
  lead: ('Harmonica', _harmonica, 60, 79),
  seed: 4,
);

/// Swing in F, 140 bpm: drums, walking double bass, piano, tenor sax.
MidiAssetSongBuilder jazzSwing() => _band(
  title: 'Jazz Swing',
  bpm: 140,
  tonic: 5,
  alterations: -1,
  a: const MidiAssetProgression([
    'Gm7', 'C7', 'Fmaj7', 'Dm7', 'Gm7', 'C7', 'Fmaj7', 'Fmaj7', //
  ]),
  b: const MidiAssetProgression([
    'Am7', 'D7', 'Gm7', 'C7', 'Fmaj7', 'Dm7', 'Gm7 C7', 'Fmaj7', //
  ]),
  // Triplets: the ride on 1, 2 and its last third, 3, 4 and its last third.
  groove: const {
    MidiDrum.ride: 'x..x.xx..x.x',
    MidiDrum.pedalHat: '...x.....x..',
    MidiDrum.kick: 'o.....o.....',
    MidiDrum.snare: '.....o.....o',
  },
  swing: 0.3,
  bass: ('Bass', _acousticBass, MidiAssetBass.walking),
  bassLow: 40,
  comps: [_comp('Piano', _piano, MidiAssetComp.shells, low: 60, pan: 45)],
  lead: ('Tenor sax', _tenorSax, 58, 79),
  rhythms: midiAssetRhythmsBusy,
  seed: 5,
);

/// A bossa nova in C, 120 bpm: drums, double bass, nylon guitar, flute.
MidiAssetSongBuilder bossaNova() => _band(
  title: 'Bossa Nova',
  bpm: 120,
  tonic: 0,
  a: const MidiAssetProgression([
    'Cmaj7', 'Cmaj7', 'Dm7', 'G7', 'Em7', 'A7', 'Dm7 G7', 'Cmaj7', //
  ]),
  b: const MidiAssetProgression([
    'Fmaj7', 'Fm6', 'Em7', 'A7', 'Dm7', 'G7', 'Cmaj7', 'Cmaj7', //
  ]),
  groove: const {
    MidiDrum.sideStick: 'x..x..x...x..x..',
    MidiDrum.closedHat: 'o.o.o.o.o.o.o.o.',
    MidiDrum.kick: 'x..ox..ox..ox..o',
  },
  bass: ('Bass', _acousticBass, MidiAssetBass.bossa),
  bassLow: 40,
  comps: [_comp('Nylon guitar', _nylonGuitar, MidiAssetComp.bossa, pan: 40)],
  lead: ('Flute', _flute, 65, 84),
  seed: 6,
);

/// Reggae in G, 76 bpm, the one drop: drums, bass, guitar, organ, trumpet.
MidiAssetSongBuilder reggaeOneDrop() => _band(
  title: 'Reggae One Drop',
  bpm: 76,
  tonic: 7,
  alterations: 1,
  a: const MidiAssetProgression([
    'G', 'C', 'G', 'D', 'G', 'C', 'D', 'G', //
  ]),
  b: const MidiAssetProgression([
    'Em', 'C', 'G', 'D', 'Em', 'C', 'D', 'G', //
  ]),
  // The one drop: the kick and the rim on beat 3 only.
  groove: const {
    MidiDrum.kick: '........X.......',
    MidiDrum.sideStick: '........x.......',
    MidiDrum.closedHat: 'x.x.x.x.x.x.x.x.',
  },
  bass: ('Bass', _fingerBass, MidiAssetBass.reggae),
  comps: [
    _comp('Guitar skank', _mutedGuitar, MidiAssetComp.skank, low: 60, pan: 90),
    _comp(
      'Organ bubble',
      _percussiveOrgan,
      MidiAssetComp.skank,
      volume: 65,
      pan: 35,
    ),
  ],
  lead: ('Trumpet', _trumpet, 62, 79),
  seed: 7,
);

/// Disco in A minor, 120 bpm: drums, octave bass, strings, brass, violins.
MidiAssetSongBuilder discoFever() => _band(
  title: 'Disco Fever',
  bpm: 120,
  tonic: 9,
  minor: true,
  a: const MidiAssetProgression([
    'Am7', 'Dm7', 'Am7', 'Dm7', 'Fmaj7', 'Em7', 'Dm7', 'E7', //
  ]),
  b: const MidiAssetProgression([
    'Fmaj7', 'G', 'Em7', 'Am7', 'Dm7', 'G', 'Fmaj7', 'Am7', //
  ]),
  groove: const {
    MidiDrum.kick: 'x...x...x...x...',
    MidiDrum.clap: '....x.......x...',
    MidiDrum.openHat: '..x...x...x...x.',
    MidiDrum.closedHat: 'o...o...o...o...',
  },
  bass: ('Bass', _fingerBass, MidiAssetBass.octaves),
  comps: [
    _comp('Strings', _strings, MidiAssetComp.pad, low: 60, volume: 70, pan: 85),
    _comp('Brass', _brass, MidiAssetComp.stabs, low: 62, volume: 75, pan: 40),
  ],
  lead: ('Violins', _violin, 67, 88),
  seed: 8,
);

/// Country in D, 116 bpm, the train beat: drums, bass, acoustic guitar, banjo, fiddle.
MidiAssetSongBuilder countryRoad() => _band(
  title: 'Country Road',
  bpm: 116,
  tonic: 2,
  alterations: 2,
  a: const MidiAssetProgression([
    'D', 'D', 'G', 'D', 'D', 'A', 'G A', 'D', //
  ]),
  b: const MidiAssetProgression([
    'G', 'G', 'D', 'D', 'A', 'G', 'A', 'D', //
  ]),
  // The train beat: the snare in eighths, accented on 2 and 4.
  groove: const {
    MidiDrum.kick: 'x.......x.......',
    MidiDrum.snare: 'o.o.X.o.o.o.X.o.',
  },
  bass: ('Bass', _fingerBass, MidiAssetBass.rootFifth),
  comps: [
    _comp('Acoustic guitar', _steelGuitar, MidiAssetComp.strum, pan: 40),
    _comp(
      'Banjo',
      _banjo,
      MidiAssetComp.arpeggio16,
      low: 62,
      volume: 70,
      pan: 90,
    ),
  ],
  lead: ('Fiddle', _fiddle, 62, 86),
  seed: 9,
);

/// Salsa in D minor, 160 bpm: the clave, cowbell and congas, bass, piano, brass, trumpet.
MidiAssetSongBuilder latinSalsa() => _band(
  title: 'Latin Salsa',
  bpm: 160,
  tonic: 2,
  minor: true,
  alterations: -1,
  a: const MidiAssetProgression([
    'Dm', 'A7', 'A7', 'Dm', 'Dm', 'A7', 'A7', 'Dm', //
  ]),
  b: const MidiAssetProgression([
    'Gm', 'Dm', 'A7', 'Dm', 'Gm', 'Dm', 'A7', 'Dm', //
  ]),
  // The 3-2 son clave, the cowbell, the congas.
  groove: const {
    MidiDrum.claves: 'x..x..x...x.x...',
    MidiDrum.cowbell: 'x...x...x...x...',
    MidiDrum.muteConga: '....o.......o...',
    MidiDrum.openConga: '......x.......x.',
    MidiDrum.lowConga: '.......x.......x',
    MidiDrum.kick: 'x.......x.......',
  },
  bass: ('Bass', _fingerBass, MidiAssetBass.tumbao),
  comps: [
    _comp('Piano montuno', _piano, MidiAssetComp.montuno, low: 62, pan: 40),
    _comp('Brass', _brass, MidiAssetComp.stabs, low: 64, volume: 80, pan: 90),
  ],
  lead: ('Trumpet', _trumpet, 64, 84),
  rhythms: midiAssetRhythmsBusy,
  seed: 10,
);

/// Electronic dance in F minor, 124 bpm: drums, synth bass, pad, arpeggio, lead.
MidiAssetSongBuilder electroDance() => _band(
  title: 'Electro Dance',
  bpm: 124,
  tonic: 5,
  minor: true,
  alterations: -4,
  a: const MidiAssetProgression([
    'Fm', 'Db', 'Ab', 'Eb', 'Fm', 'Db', 'Ab', 'Eb', //
  ]),
  b: const MidiAssetProgression([
    'Db', 'Eb', 'Fm', 'Fm', 'Db', 'Eb', 'C', 'Fm', //
  ]),
  groove: const {
    MidiDrum.kick: 'x...x...x...x...',
    MidiDrum.clap: '....x.......x...',
    MidiDrum.openHat: '..x...x...x...x.',
    MidiDrum.closedHat: 'oxo.oxo.oxo.oxo.',
  },
  bass: ('Synth bass', _synthBass, MidiAssetBass.eighths),
  comps: [
    _comp('Pad', _warmPad, MidiAssetComp.pad, low: 60, volume: 70),
    _comp(
      'Arpeggio',
      _sawLead,
      MidiAssetComp.arpeggio16,
      low: 67,
      volume: 60,
      pan: 90,
    ),
  ],
  lead: ('Lead', _squareLead, 65, 84),
  seed: 11,
);

/// Hip hop in C minor, 90 bpm: drums, bass, electric piano, vibraphone, muted trumpet.
MidiAssetSongBuilder hipHopBeat() => _band(
  title: 'Hip Hop Beat',
  bpm: 90,
  tonic: 0,
  minor: true,
  alterations: -3,
  a: const MidiAssetProgression([
    'Cm7', 'Cm7', 'Abmaj7', 'Abmaj7', 'Fm7', 'Fm7', 'G7', 'G7', //
  ]),
  groove: const {
    MidiDrum.kick: 'x......x..x.....',
    MidiDrum.snare: '....X.......X...',
    MidiDrum.closedHat: 'x.x.x.x.x.x.x.x.',
  },
  swing: 0.15,
  bass: ('Bass', _fingerBass, MidiAssetBass.downbeat),
  comps: [
    _comp('Electric piano', _electricPiano, MidiAssetComp.pad, low: 58),
    _comp(
      'Vibraphone',
      _vibraphone,
      MidiAssetComp.arpeggio,
      low: 67,
      volume: 60,
      pan: 90,
    ),
  ],
  lead: ('Muted trumpet', _mutedTrumpet, 62, 79),
  seed: 12,
);

/// A march in B flat, 116 bpm: snare, bass drum, tuba, trombones, brass, trumpet.
MidiAssetSongBuilder march() => _band(
  title: 'March',
  bpm: 116,
  tonic: 10,
  alterations: -2,
  a: const MidiAssetProgression([
    'Bb', 'Bb', 'F7', 'F7', 'Bb', 'Eb', 'F7', 'Bb', //
  ]),
  b: const MidiAssetProgression([
    'Eb', 'Eb', 'Bb', 'Bb', 'F7', 'F7', 'Bb F7', 'Bb', //
  ]),
  groove: const {
    MidiDrum.snare: 'X.x.x.xxX.x.x.xx',
    MidiDrum.kick: 'x.......x.......',
  },
  bass: ('Tuba', _tuba, MidiAssetBass.rootFifth),
  comps: [
    _comp('Trombones', _trombone, MidiAssetComp.block, low: 50, pan: 40),
    _comp('Brass', _brass, MidiAssetComp.waltz, low: 58, volume: 70, pan: 90),
  ],
  lead: ('Trumpet', _trumpet, 62, 82),
  seed: 13,
);

/// A musette waltz in A minor, 150 bpm: drums, double bass, accordions.
MidiAssetSongBuilder musetteWaltz() => _band(
  title: 'Musette Waltz',
  bpm: 150,
  beatsPerBar: 3,
  tonic: 9,
  minor: true,
  a: const MidiAssetProgression([
    'Am', 'Am', 'E7', 'E7', 'E7', 'E7', 'Am', 'Am', //
  ]),
  b: const MidiAssetProgression([
    'Dm', 'Dm', 'Am', 'Am', 'E7', 'E7', 'Am', 'Am', //
  ]),
  // Eighths of a bar of three: the kick on 1, the brushes on 2 and 3.
  groove: const {MidiDrum.kick: 'x.....', MidiDrum.snare: '..o.o.'},
  bass: ('Bass', _acousticBass, MidiAssetBass.downbeat),
  bassLow: 40,
  comps: [_comp('Accordion chords', _accordion, MidiAssetComp.waltz, pan: 40)],
  lead: ('Accordion', _accordion, 64, 86),
  rhythms: midiAssetRhythms3,
  seed: 14,
);

/// Gospel in F, 84 bpm: drums, tambourine, bass, organ, piano, choir, voice.
MidiAssetSongBuilder gospelOrgan() => _band(
  title: 'Gospel Organ',
  bpm: 84,
  tonic: 5,
  alterations: -1,
  a: const MidiAssetProgression([
    'F', 'Bb', 'F', 'C7', 'F', 'Bb', 'C7', 'F', //
  ]),
  b: const MidiAssetProgression([
    'Bb', 'Bb', 'F', 'Dm', 'Gm7', 'C7', 'F', 'F', //
  ]),
  groove: const {
    MidiDrum.kick: 'x.....x.x.......',
    MidiDrum.snare: '....X.......X...',
    MidiDrum.closedHat: 'x.x.x.x.x.x.x.x.',
    MidiDrum.tambourine: '....x.......x...',
  },
  swing: 0.25,
  bass: ('Bass', _fingerBass, MidiAssetBass.roots),
  comps: [
    _comp('Organ', _drawbarOrgan, MidiAssetComp.pad, low: 53, pan: 40),
    _comp('Piano', _piano, MidiAssetComp.block, low: 60, volume: 70, pan: 85),
    _comp('Choir', _choir, MidiAssetComp.pad, low: 60, volume: 65),
  ],
  lead: ('Voice', _voice, 60, 79),
  seed: 15,
);

/// A piano piece: the left hand [left] (comping or bass), the melody in the
/// right hand over [a] then [b], a last chord.
MidiAssetSongBuilder _pianoPiece({
  required String title,
  required double bpm,
  required int tonic,
  required MidiAssetProgression a,
  required MidiAssetProgression b,
  required void Function(
    MidiAssetSongBuilder song,
    MidiAssetPart left,
    MidiAssetProgression progression,
    int fromBar,
    MidiAssetRandom random,
  )
  left,
  required int seed,
  int beatsPerBar = 4,
  bool minor = false,
  int alterations = 0,
  double swing = 0,
  int low = 62,
  int high = 86,
  List<List<(double, double)>> rhythms = midiAssetRhythms4,
}) {
  var song = MidiAssetSongBuilder(
    title: title,
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    keyAlterations: alterations,
    minor: minor,
  );
  var random = MidiAssetRandom(seed);
  var right = song.part('Piano right hand', channel: 0, pan: 70);
  var leftPart = song.part('Piano left hand', channel: 0, pan: 58);
  var scale = midiAssetScale(tonic, minor: minor);
  var bar = 0;
  for (var progression in [a, b]) {
    left(song, leftPart, progression, bar, random);
    midiAssetMelody(
      song,
      right,
      progression,
      fromBar: bar,
      bars: progression.bars.length,
      scale: scale,
      rhythms: rhythms,
      random: random,
      low: low,
      high: high,
      swing: swing,
      velocity: 85,
    );
    bar += progression.bars.length;
  }
  var last = MidiChord.parse(b.bars.last.split(' ').last);
  leftPart.chord(song.bar(bar), beatsPerBar.toDouble(), [
    last.bass(36),
    ...last.voicing(48, count: 3),
  ], 75);
  right.chord(
    song.bar(bar),
    beatsPerBar.toDouble(),
    last.voicing(60, count: 4),
    70,
  );
  return song;
}

/// A piano nocturne in A minor, 66 bpm: arpeggios in the left hand.
MidiAssetSongBuilder pianoNocturne() => _pianoPiece(
  title: 'Piano Nocturne',
  bpm: 66,
  tonic: 9,
  minor: true,
  a: const MidiAssetProgression([
    'Am', 'F', 'C', 'G', 'Am', 'Dm', 'E7', 'Am', //
  ]),
  b: const MidiAssetProgression([
    'F', 'G', 'C', 'Am', 'Dm', 'E7', 'Am', 'Am', //
  ]),
  left: (song, left, progression, fromBar, random) => midiAssetComp(
    song,
    left,
    progression,
    MidiAssetComp.arpeggio,
    fromBar: fromBar,
    low: 45,
    velocity: 60,
    random: random,
  ),
  seed: 16,
);

/// A piano ragtime in C, 100 bpm: the stride left hand.
MidiAssetSongBuilder pianoRagtime() => _pianoPiece(
  title: 'Piano Ragtime',
  bpm: 100,
  tonic: 0,
  a: const MidiAssetProgression([
    'C', 'C', 'A7', 'A7', 'D7', 'G7', 'C', 'G7', //
  ]),
  b: const MidiAssetProgression([
    'F', 'F', 'C', 'A7', 'D7', 'G7', 'C G7', 'C', //
  ]),
  left: (song, left, progression, fromBar, random) => midiAssetComp(
    song,
    left,
    progression,
    MidiAssetComp.stride,
    fromBar: fromBar,
    velocity: 70,
    random: random,
  ),
  rhythms: midiAssetRhythmsBusy,
  seed: 17,
);

/// A twelve-bar piano boogie-woogie in C, 120 bpm: the walking left hand.
MidiAssetSongBuilder pianoBoogie() => _pianoPiece(
  title: 'Piano Boogie',
  bpm: 120,
  tonic: 0,
  a: const MidiAssetProgression([
    'C7', 'F7', 'C7', 'C7', 'F7', 'F7', 'C7', 'C7', 'G7', 'F7', 'C7', 'G7', //
  ]),
  b: const MidiAssetProgression([
    'C7', 'F7', 'C7', 'C7', 'F7', 'F7', 'C7', 'C7', 'G7', 'F7', 'C7', 'C7', //
  ]),
  swing: 0.22,
  left: (song, left, progression, fromBar, random) => midiAssetBass(
    song,
    left,
    progression,
    MidiAssetBass.boogie,
    fromBar: fromBar,
    swing: 0.22,
    random: random,
  ),
  rhythms: midiAssetRhythmsBusy,
  seed: 18,
);

/// A piano waltz in G, 132 bpm: the bass and the chords of the left hand.
MidiAssetSongBuilder pianoWaltz() => _pianoPiece(
  title: 'Piano Waltz',
  bpm: 132,
  beatsPerBar: 3,
  tonic: 7,
  alterations: 1,
  a: const MidiAssetProgression([
    'G', 'G', 'D7', 'D7', 'D7', 'D7', 'G', 'G', //
  ]),
  b: const MidiAssetProgression([
    'C', 'C', 'G', 'G', 'A7', 'D7', 'G', 'G', //
  ]),
  left: (song, left, progression, fromBar, random) {
    midiAssetBass(
      song,
      left,
      progression,
      MidiAssetBass.downbeat,
      fromBar: fromBar,
      random: random,
    );
    midiAssetComp(
      song,
      left,
      progression,
      MidiAssetComp.waltz,
      fromBar: fromBar,
      low: 52,
      velocity: 60,
      random: random,
    );
  },
  rhythms: midiAssetRhythms3,
  seed: 19,
);

/// A piano ballad in D, 72 bpm: the chords of the left hand.
MidiAssetSongBuilder pianoBallad() => _pianoPiece(
  title: 'Piano Ballad',
  bpm: 72,
  tonic: 2,
  alterations: 2,
  a: const MidiAssetProgression([
    'D', 'A', 'Bm', 'G', 'D', 'A', 'G', 'A', //
  ]),
  b: const MidiAssetProgression([
    'Bm', 'G', 'D', 'A', 'Em', 'G', 'A', 'D', //
  ]),
  left: (song, left, progression, fromBar, random) {
    midiAssetBass(
      song,
      left,
      progression,
      MidiAssetBass.downbeat,
      fromBar: fromBar,
      random: random,
    );
    midiAssetComp(
      song,
      left,
      progression,
      MidiAssetComp.block,
      fromBar: fromBar,
      low: 50,
      velocity: 55,
      random: random,
    );
  },
  seed: 20,
);
