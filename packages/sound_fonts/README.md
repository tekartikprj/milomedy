# milomedy_sound_fonts

The SoundFont library of the MIDI engine, pure Dart (VM, dart2js, dart2wasm):

- **Storage** through `fs_shim`: files on io, IndexedDB on the web. The SoundFonts
  are `<id>.sf2` files next to an `index.json`.
- **Download** of a `MidiSoundFontSource`, with progress. Its size and its git blob
  id are checked when the source gives them.
- **Import** of any `.sf2` file. It is read first, so a file that is not a
  SoundFont is refused, and the same bytes are never added twice (SHA-256).
- **The entries** keep the name, size, preset count, copyright, author and comments
  of each SoundFont: its licence is usually in the copyright or the comments.
- **The default** SoundFont, and `ensure(source)` to download it on first use.
- **A built-in fallback**, the tiny SoundFont of `milomedy_midi_synth_sf2` (a sine,
  a noise), always there: something plays offline, with no licence question.

## GeneralUser GS

`midiGeneralUserGs(url: ...)` is GeneralUser GS 2.0.3 by S. Christian Collins: a
General MIDI and GS bank, 261 presets and 13 drum kits, 32 MB, free for any use.
Its licence asks not to link directly to the author's download files: "Either link
to my website, or provide your own local copy instead". So an app downloads a copy
it hosts, given as `url`, and the download is checked against the file of version
2.0.3 (size and git blob id). `midiGeneralUserGsUpstreamUrl`, the file in its
repository at the commit of that version, is for development and tools.

## Setup

```yaml
dependencies:
  milomedy_sound_fonts:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/sound_fonts
```

## Use

```dart
var library = MidiSoundFontLibrary(
  fileSystem: fileSystemDefault, // files on io, IndexedDB on the web
  path: 'sound_fonts',
);
var entry = await library.ensure(
  midiGeneralUserGs(url: myHostedCopy),
  onProgress: (received, total) => print('$received / $total'),
);
await library.setDefault(entry.id);
await player.loadSoundFont('gm', await library.read(await library.defaultId()));
```
