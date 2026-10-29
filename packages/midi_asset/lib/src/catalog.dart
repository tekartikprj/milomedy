/// The catalog of the songs: their id, title, style and instruments, built
/// in code or read as files (`lib/midi/<id>.mid`).
library;

import 'dart:typed_data';

import 'builder.dart';
import 'songs.dart';

/// A song of the catalog.
class MidiAssetSong {
  /// Its id, the name of its file (`rock_anthem`).
  final String id;

  /// Its title.
  final String title;

  /// Its style.
  final String style;

  /// Its instruments, in words.
  final String instruments;

  /// True for a piano piece.
  final bool pianoOnly;

  final MidiAssetSongBuilder Function() _build;

  const MidiAssetSong._(
    this.id,
    this.title,
    this.style,
    this.instruments,
    this._build, {
    this.pianoOnly = false,
  });

  /// The song, built in code.
  MidiAssetSongBuilder build() => _build();

  /// The bytes of its MIDI file, made in code (the same as its file).
  Uint8List toBytes() => build().toBytes();

  /// Its file in the package (`midi/<id>.mid` in `lib/`).
  String get path => 'midi/$id.mid';

  /// Its Flutter asset, once listed in the app's pubspec
  /// (`packages/milomedy_midi_asset/midi/<id>.mid`).
  String get flutterAsset => 'packages/milomedy_midi_asset/$path';

  @override
  String toString() => 'MidiAssetSong($id)';
}

/// The songs: fifteen for a band, then five piano pieces.
const midiAssetSongs = <MidiAssetSong>[
  MidiAssetSong._(
    'rock_anthem',
    'Rock Anthem',
    'rock',
    'drums, bass, distortion guitar, rock organ, lead guitar',
    rockAnthem,
  ),
  MidiAssetSong._(
    'pop_ballad',
    'Pop Ballad',
    'pop',
    'drums, bass, piano, strings, flute',
    popBallad,
  ),
  MidiAssetSong._(
    'funk_groove',
    'Funk Groove',
    'funk',
    'drums, slap bass, clavinet, brass, tenor sax',
    funkGroove,
  ),
  MidiAssetSong._(
    'blues_shuffle',
    'Blues Shuffle',
    'blues',
    'drums, bass, organ, guitar, harmonica',
    bluesShuffle,
  ),
  MidiAssetSong._(
    'jazz_swing',
    'Jazz Swing',
    'jazz',
    'drums, double bass, piano, tenor sax',
    jazzSwing,
  ),
  MidiAssetSong._(
    'bossa_nova',
    'Bossa Nova',
    'bossa nova',
    'drums, double bass, nylon guitar, flute',
    bossaNova,
  ),
  MidiAssetSong._(
    'reggae_one_drop',
    'Reggae One Drop',
    'reggae',
    'drums, bass, guitar, organ, trumpet',
    reggaeOneDrop,
  ),
  MidiAssetSong._(
    'disco_fever',
    'Disco Fever',
    'disco',
    'drums, bass, strings, brass, violins',
    discoFever,
  ),
  MidiAssetSong._(
    'country_road',
    'Country Road',
    'country',
    'drums, bass, acoustic guitar, banjo, fiddle',
    countryRoad,
  ),
  MidiAssetSong._(
    'latin_salsa',
    'Latin Salsa',
    'salsa',
    'clave, cowbell, congas, bass, piano, brass, trumpet',
    latinSalsa,
  ),
  MidiAssetSong._(
    'electro_dance',
    'Electro Dance',
    'electronic',
    'drums, synth bass, pad, arpeggio, lead',
    electroDance,
  ),
  MidiAssetSong._(
    'hip_hop_beat',
    'Hip Hop Beat',
    'hip hop',
    'drums, bass, electric piano, vibraphone, muted trumpet',
    hipHopBeat,
  ),
  MidiAssetSong._(
    'march',
    'March',
    'march',
    'snare, bass drum, tuba, trombones, brass, trumpet',
    march,
  ),
  MidiAssetSong._(
    'musette_waltz',
    'Musette Waltz',
    'musette',
    'drums, double bass, accordions',
    musetteWaltz,
  ),
  MidiAssetSong._(
    'gospel_organ',
    'Gospel Organ',
    'gospel',
    'drums, tambourine, bass, organ, piano, choir, voice',
    gospelOrgan,
  ),
  MidiAssetSong._(
    'piano_nocturne',
    'Piano Nocturne',
    'classical',
    'piano',
    pianoNocturne,
    pianoOnly: true,
  ),
  MidiAssetSong._(
    'piano_ragtime',
    'Piano Ragtime',
    'ragtime',
    'piano',
    pianoRagtime,
    pianoOnly: true,
  ),
  MidiAssetSong._(
    'piano_boogie',
    'Piano Boogie',
    'boogie-woogie',
    'piano',
    pianoBoogie,
    pianoOnly: true,
  ),
  MidiAssetSong._(
    'piano_waltz',
    'Piano Waltz',
    'waltz',
    'piano',
    pianoWaltz,
    pianoOnly: true,
  ),
  MidiAssetSong._(
    'piano_ballad',
    'Piano Ballad',
    'ballad',
    'piano',
    pianoBallad,
    pianoOnly: true,
  ),
];

/// The song [id], null when not in the catalog.
MidiAssetSong? midiAssetSong(String id) =>
    midiAssetSongs.where((song) => song.id == id).firstOrNull;
