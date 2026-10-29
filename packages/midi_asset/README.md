# milomedy_midi_asset

MIDI files made in Dart, free to use (MIT, like the rest of the repository): twenty
short songs in various styles, fifteen for a band and five piano pieces. They are
General MIDI files (format 1, a conductor track then a track per instrument, drums
on channel 10) to test a player or to play with any General MIDI SoundFont.

The songs are written in code. The files in `lib/midi/` are what this code makes,
and the same bytes come out on the VM, dart2js and dart2wasm.

| Id | Title | Style | Instruments | Length |
|---|---|---|---|---|
| `rock_anthem` | Rock Anthem | rock | drums, bass, distortion guitar, rock organ, lead guitar | 36 s |
| `pop_ballad` | Pop Ballad | pop | drums, bass, piano, strings, flute | 61 s |
| `funk_groove` | Funk Groove | funk | drums, slap bass, clavinet, brass, tenor sax | 44 s |
| `blues_shuffle` | Blues Shuffle | blues | drums, bass, organ, guitar, harmonica | 68 s |
| `jazz_swing` | Jazz Swing | jazz | drums, double bass, piano, tenor sax | 33 s |
| `bossa_nova` | Bossa Nova | bossa nova | drums, double bass, nylon guitar, flute | 39 s |
| `reggae_one_drop` | Reggae One Drop | reggae | drums, bass, guitar, organ, trumpet | 61 s |
| `disco_fever` | Disco Fever | disco | drums, bass, strings, brass, violins | 39 s |
| `country_road` | Country Road | country | drums, bass, acoustic guitar, banjo, fiddle | 40 s |
| `latin_salsa` | Latin Salsa | salsa | clave, cowbell, congas, bass, piano, brass, trumpet | 29 s |
| `electro_dance` | Electro Dance | electronic | drums, synth bass, pad, arpeggio, lead | 37 s |
| `hip_hop_beat` | Hip Hop Beat | hip hop | drums, bass, electric piano, vibraphone, muted trumpet | 51 s |
| `march` | March | march | snare, bass drum, tuba, trombones, brass, trumpet | 40 s |
| `musette_waltz` | Musette Waltz | musette | drums, double bass, accordions | 23 s |
| `gospel_organ` | Gospel Organ | gospel | drums, tambourine, bass, organ, piano, choir, voice | 55 s |
| `piano_nocturne` | Piano Nocturne | classical | piano | 63 s |
| `piano_ragtime` | Piano Ragtime | ragtime | piano | 41 s |
| `piano_boogie` | Piano Boogie | boogie-woogie | piano | 51 s |
| `piano_waltz` | Piano Waltz | waltz | piano | 24 s |
| `piano_ballad` | Piano Ballad | ballad | piano | 57 s |

## Setup

```yaml
dependencies:
  milomedy_midi_asset:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_asset
```

## Use

In code, on any platform:

```dart
var asset = midiAssetSong('bossa_nova')!;
var bytes = asset.toBytes(); // the MIDI file
var song = MidiSong.fromBytes(bytes); // milomedy_midi_engine
```

As Flutter assets, listed in the app's pubspec:

```yaml
flutter:
  assets:
    - packages/milomedy_midi_asset/midi/bossa_nova.mid
```

```dart
var data = await rootBundle.load(midiAssetSong('bossa_nova')!.flutterAsset);
```

## The arranger

The songs are made with the tools exported here, to write more:

- `MidiAssetSongBuilder`: tempo, time signature, key, parts (a channel, a General
  MIDI program, volume, pan, reverb), notes in beats.
- `MidiChord`: chord symbols (`C`, `Am7`, `F#m7b5`, `Bb9`...), their bass, voicing
  and tones.
- The patterns: drum grooves written as steps (`X` accent, `x` hit, `o` ghost), bass
  lines (`MidiAssetBass`: walking, funk, reggae, tumbao, boogie...), accompaniments
  (`MidiAssetComp`: pad, skank, montuno, stride, bossa...), melodies on a scale.
- `MidiAssetRandom`: a small random generator from a seed, the same on every
  platform, for the variations.

After a change, `dart run tool/generate.dart` writes the files again; a test checks
that they are up to date.
