# milomedy_sound_fonts

The SoundFont library of the milomedy MIDI engine: the `.sf2` files an app
downloads or imports, kept with their name, presets and licence notes, the
default one, and a built-in fallback. Pure Dart: Dart VM, Flutter, dart2js and
dart2wasm; storage through `fs_shim` (files on io, IndexedDB on the web).

## Getting started

Not on pub.dev, git dependencies (`fs_shim` for the storage):

```yaml
dependencies:
  fs_shim: ">=2.7.0"
  milomedy_sound_fonts:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/sound_fonts
```

Download GeneralUser GS on first use and make it the default:

```dart
import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';

/// One library per folder in the app.
final library = MidiSoundFontLibrary(
  fileSystem: fileSystemDefault, // files on io, IndexedDB on the web
  path: 'sound_fonts',
);

/// The bytes of the default SoundFont: GeneralUser GS, downloaded from
/// [hostedCopy] (a copy the app hosts) the first time.
Future<Uint8List> defaultSoundFont(Uri hostedCopy) async {
  var entry = await library.ensure(
    midiGeneralUserGs(url: hostedCopy),
    onProgress: (received, total) => print('$received / $total'),
  );
  await library.setDefault(entry.id);
  return library.read(await library.defaultId());
}
```

Give the bytes to the player of milomedy_midi_engine
(`player.loadSoundFont('gm', bytes)`), or read them with `MidiSoundFont` of
milomedy_midi_synth_sf2. [example/main.dart](example/main.dart) imports the
`.sf2` files given and lists the library (`dart run example/main.dart
my_font.sf2`).

## What it does

- **Download** a `MidiSoundFontSource` with its progress; its size, SHA-256
  and git blob id are checked when the source gives them, whatever the
  location.
- **Alternate locations**: a source lists mirrors (`locations`) tried in
  order after its `url`, and a `path` that a sound server of the user's
  choice serves (`download(soundServer: Uri.parse('http://my-server/'))`,
  tried first). A location fails on an http error, on 30 s with no byte
  (`idleTimeout`) or on a file that is not the one expected; the
  `MidiSoundFontDownloadException` lists each attempt.
- **Resume and cancel**: the bytes go to `<id>.sf2.part` as they come (a few
  MB at a time), `MidiSoundFontDownloadCancel` stops at the next chunk and
  keeps them, the next download asks only for the rest (`Range`, a 200
  answer starts over); `partSize(id)`, `deletePart(id)`.
- **The catalog** (`MidiSoundFontCatalog`): the SoundFonts an app offers, as
  the JSON `catalog.json` next to them (`fromJson`, `toJson`, `fetch(url)`,
  `merge(newer)` for the copy built into the app and the one fetched), the
  layout of a sound server (`midiSoundFontCatalogPath`).
- **Import** any `.sf2` file (picked, dropped, fetched): it is read first, a
  file that is not a SoundFont is refused, the same bytes are never added
  twice (SHA-256).
- **Entries** (`list()`, `entry(id)`) keep the name, size, preset count,
  copyright, author and comments of each SoundFont: its licence is usually in
  the copyright or the comments.
- **The default** (`defaultId()`, `setDefault(id)`), and `ensure(source)` to
  download it on first use.
- **A built-in fallback**, id `tiny` (the tiny SoundFont of
  milomedy_midi_synth_sf2: a sine, a noise), always there and the default
  until another is set: something plays offline, with no licence question.

## GeneralUser GS

`midiGeneralUserGs(url: ...)` is GeneralUser GS 2.0.3 by S. Christian Collins:
a General MIDI and GS bank, 261 presets and 13 drum kits, 32 MB, free for any
use. Its licence asks not to link directly to the author's download files:
"Either link to my website, or provide your own local copy instead". So an app
downloads a copy it hosts, given as `url`, and the download is checked against
the file of version 2.0.3 (size, SHA-256 `midiGeneralUserGsSha256` and git
blob id).
`midiGeneralUserGsUpstreamUrl`, the file in its repository at the commit of
that version, is for development and tools.

## SF3

An SF3 is an SF2 whose samples are compressed, each one an Ogg Vorbis stream
(the format of MuseScore, read by FluidSynth and SpessaSynth): GeneralUser GS
takes 9 MB instead of 32. The synth reads SF2 only, so the library turns an
SF3 into the SF2 it stands for when it is downloaded or imported
(`midiSoundFontDecompress`, pure Dart through `milomedy_vorbis`), once: it
keeps the SF2, and the SHA-256 of the SF3 in `originalSha256` (a second import
of the same file is not decoded again). `onUnpack` tells the samples done.

- GeneralUser GS: 920 samples, 4 s on the VM, 10 s in Chrome with dart2js
  (the event loop runs between samples, 60 ms at most), 42 s with dart2wasm.
- `midiGeneralUserGsSf3(url: ...)`: GeneralUser GS 2.0.3 in SF3 at Vorbis
  quality 6, 9 110 502 bytes, `midiGeneralUserGsSf3Sha256`; its samples at a
  median signal to noise ratio of 32 dB against the SF2 (10.8 dB for the
  worst, a noise), the same frames and loops.
- A catalog lists the SF3 apart (`compressedSoundFonts`): an app built before
  SF3 reads `soundFonts` only. `sameAs` links the SF2 and the SF3 of the same
  bank: an app offers one of them.
- To make one (io, ffmpeg with libvorbis on the PATH):
  `dart run tool/compress_sound_font.dart in.sf2 out.sf3 --quality 6`, which
  checks the result (frames, loops) and prints the signal to noise ratios;
  `package:milomedy_sound_fonts/sf3_ffmpeg.dart` in code. The same input
  gives the same bytes (ffmpeg `+bitexact`).
- `midiTinySoundFontSf3Bytes()`: the tiny SoundFont in SF3, for tests.
- In a browser, by hand: copy an SF3 to `.local/benchmark/sound_font.sf3`,
  then `dart test -p chrome test/sf3_web_test_manual.dart`.

## Good to know

- Use one `MidiSoundFontLibrary` per folder: a library reads its index once,
  another instance on the same folder does not see its later changes. The
  changes of one library run one after the other (imports at once are safe).
- `ensure(source)` finds the file already imported under another id without
  downloading it when the source gives its size and git blob id (GeneralUser
  GS does); otherwise it downloads, then recognizes it.
- A download is kept in memory until checked (32 MB for GeneralUser GS).
- `delete(id)` cannot delete the built-in one; the default goes back to it.
