---
name: milomedy-midi-asset
description: >-
  Use when a Dart or Flutter app or test needs free General MIDI files (MIT)
  or writes songs in code with milomedy_midi_asset: midiAssetSongs and
  midiAssetSong(id) (MidiAssetSong: id, title, style, instruments,
  pianoOnly, toBytes, build, path, flutterAsset), the lib/midi/*.mid files as
  Flutter package assets, and the arranger (MidiAssetSongBuilder,
  MidiAssetPart, MidiChord, MidiAssetBass, MidiAssetComp, drum patterns,
  MidiAssetRandom), tool/generate.dart.
---

# MIDI songs made in Dart (milomedy_midi_asset)

Twenty short General MIDI songs (fifteen for a band, five piano pieces),
written in code with a small arranger, and the same songs as files in
`lib/midi/`. Format 1: a conductor track (tempo, time and key signatures)
then a track per instrument, drums on channel 10 (index 9).

## Guidelines

* Dependency (git, public repo, not on pub.dev):
  ```yaml
  dependencies:
    milomedy_midi_asset:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/midi_asset
  ```
  One import: `package:milomedy_midi_asset/midi_asset.dart`. Pure Dart, every
  platform; it depends on `tekartik_midi` (writer) only.
* `midiAssetSongs` lists them (ids: `rock_anthem`, `bossa_nova`,
  `piano_waltz`...), `midiAssetSong(id)` gives one or null.
  `song.toBytes()` makes the MIDI file in code, the same bytes as
  `lib/midi/<id>.mid` (a test checks it), on the VM, dart2js and dart2wasm.
* To play one: `MidiSong.fromBytes(bytes).toTimeline()` with
  `milomedy_midi_engine`, then a General MIDI SoundFont
  (`milomedy_midi_synth_sf2`) for the real instruments, or any MIDI player.
* As Flutter assets, list the files in the app's pubspec
  (`- packages/milomedy_midi_asset/midi/bossa_nova.mid`) and load
  `rootBundle.load(song.flutterAsset)`. Code (`toBytes`) needs no asset.
* Writing a song: `MidiAssetSongBuilder(title:, bpm:, beatsPerBar:,
  keyAlterations:, minor:)`, `part(name, channel:, program:, volume:, pan:,
  reverb:)`, `part.note(beat, beats, key, velocity)` / `chord(...)` in beats
  (quarter notes), `bar(n)` for the first beat of a bar, then `toBytes()`.
  A note of a key is cut where the same key starts again; notes out of
  0..127 or of no length are dropped.
* `MidiChord.parse('F#m7b5')` (roots C to B with `#`/`b`; qualities `''`,
  `m`, `7`, `maj7`, `m7`, `m7b5`, `dim`, `dim7`, `aug`, `sus4`, `6`, `m6`,
  `9`, `m9`, `5`; anything else, the empty string included, is a
  `FormatException`): `bass()`, `voicing(low, count:)`, `tones(low, high)`.
* `MidiAssetRandom(seed)` gives the same values on every platform (exact in
  JS numbers); avoid the seeds -1 and 65536 (a constant generator).
* After changing a song: `dart run tool/generate.dart` writes `lib/midi/`
  again; `test/midi_files_test.dart` fails until then.

## Examples

### List the songs and get a file

```dart
import 'package:milomedy_midi_asset/midi_asset.dart';

void main() {
  for (var song in midiAssetSongs.where((song) => song.pianoOnly)) {
    print('${song.id}: ${song.title} (${song.style})');
  }
  var bytes = midiAssetSong('jazz_swing')!.toBytes();
  print('jazz_swing.mid: ${bytes.length} bytes');
}
```

### Write a short song

```dart
import 'package:milomedy_midi_asset/midi_asset.dart';

void main() {
  var builder = MidiAssetSongBuilder(title: 'Two chords', bpm: 100);
  var piano = builder.part('Piano', channel: 0);
  var drums = builder.part('Drums', channel: midiAssetDrumChannel);
  for (var (bar, symbol) in [(0, 'C'), (1, 'G7')]) {
    var chord = MidiChord.parse(symbol);
    piano.chord(builder.bar(bar), 4, chord.voicing(60));
    piano.note(builder.bar(bar), 4, chord.bass());
    for (var beat = 0; beat < 4; beat++) {
      drums.note(builder.bar(bar) + beat, 0.25, beat.isEven ? 36 : 38);
    }
  }
  var bytes = builder.toBytes(); // a format 1 MIDI file
  print('${bytes.length} bytes, ${builder.length} beats');
}
```
