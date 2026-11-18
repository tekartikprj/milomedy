---
name: milomedy-sound-fonts
description: >-
  Use when an app keeps SoundFonts (.sf2, .sf3) for the milomedy MIDI engine
  with milomedy_sound_fonts: MidiSoundFontLibrary (list, entry, read, import,
  download, ensure, setDefault, defaultId, delete) on an fs_shim file system
  (files on io, IndexedDB on the web), MidiSoundFontSource and its size and
  git blob checks, midiGeneralUserGs and midiGeneralUserGsSf3 (a hosted copy,
  its licence), SF3 turned into SF2 (midiSoundFontDecompress, in a web
  worker with midiSoundFontWorkerDecompressor and setupMidiSoundFontWorker)
  or kept as SF3 and played per song (keepCompressed, presets(id),
  MidiSoundFontSampler, midiSoundFontSampler, samplesOf, soundFont,
  MidiSoundFontDefinition, midiSoundFontNotes), or made with ffmpeg (midiSoundFontCompress), the catalog
  (compressedSoundFonts, sameAs), the built-in 'tiny' fallback, and testing
  with a memory file system and an http MockClient.
---

# SoundFont library (milomedy_sound_fonts)

Pure Dart (VM, Flutter, dart2js, dart2wasm). The SoundFonts an app downloads
or imports, stored through `fs_shim` as `<id>.sf2` files next to an
`index.json`, with the default one and a built-in fallback.

## Guidelines

* Dependencies (git, public repo, not on pub.dev), plus `fs_shim` for the
  file system:
  ```yaml
  dependencies:
    fs_shim: ">=2.7.0"
    milomedy_sound_fonts:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/sound_fonts
  ```
* Import `package:milomedy_sound_fonts/sound_fonts.dart`.
  `MidiSoundFontLibrary(fileSystem: fileSystemDefault, path: 'sound_fonts')`
  (`fileSystemDefault` of `package:fs_shim/fs_shim.dart`: files on io,
  IndexedDB on the web). Pass `client:` (an `http.Client`) for the downloads,
  a new one is made per download otherwise.
* One library per folder for the whole app: a library reads `index.json`
  once, another instance on the same folder does not see its later changes.
  Changes of one library (import, download, setDefault, delete) run one
  after the other.
* `list()` gives the built-in entry first (`builtIn: true`, id
  `MidiSoundFontLibrary.builtInId`, `'tiny'`: the tiny SoundFont of
  milomedy_midi_synth_sf2), then the others. `defaultId()` is `'tiny'` until
  `setDefault(id)`. `read(id)` gives the bytes (`ArgumentError` for an
  unknown id).
* `import(bytes, name:)` parses the file first (a non SoundFont throws), its
  id is a slug of the name (`_2`, `_3` when taken); the same bytes already
  there return the existing entry (SHA-256).
* `download(source, onProgress:, cancel:, soundServer:, idleTimeout:)` tries
  `source.candidates(soundServer:)` in order: the sound server (when the
  source has a `path`), `url`, `locations`. A location fails on an http
  error, on `idleTimeout` (30 s) with no byte, or on a file that is not the
  expected one (size, `sha256`, `gitBlobSha1`, a SoundFont); the next is
  tried. None: `MidiSoundFontDownloadException` with `attempts` (url, error
  each); nothing is added. The entry's `url` is the location used.
* The bytes go to `<id>.sf2.part` as they come (flushed every 4 MB): a
  `MidiSoundFontDownloadCancel` stops at the next chunk with
  `MidiSoundFontDownloadCancelledException`, the part kept; the next download
  resumes with `Range: bytes=<part>-` (a 200 answer starts over); a complete
  part is not downloaded again. `partSize(id)`, `deletePart(id)` for the
  screen (resume, forget).
* `ensure(source, ...)` returns the entry of `source.id`, or the same file
  imported under another id (`sameFile(source)`: by `sha256`, else by `size`
  and `gitBlobSha1`), or downloads it.
* `MidiSoundFontCatalog` is the `catalog.json` of an app's SoundFonts
  (`{"version": 1, "soundFonts": [{id, name, version, size, sha256,
  gitBlobSha1, presets, licence, licencePath, path, locations}]}`):
  `fromJson(json, base:)` (a `path` below `base` when no location; bad
  entries skipped), `toJson()`, `source(id)`, `builtIn.merge(fetched)`
  (fetched entries win, new ones after), `fetch(url, client:)`.
  `midiSoundServerUri(server, path)` and `midiSoundFontCatalogPath`
  (`public/sound_fonts/catalog.json`) are the sound server layout.
* GeneralUser GS (`midiGeneralUserGs(url: hostedCopy)`): its licence asks not
  to link to the author's download files, so the app hosts a copy;
  `midiGeneralUserGsUpstreamUrl` is for development and tools only.
* SF3 (an SF2 whose samples are Ogg Vorbis streams, 9 MB instead of 32 for
  GeneralUser GS): `import` and `download` turn it into the SF2 it stands for
  (`midiSoundFontDecompress`, pure Dart, a few seconds: `onUnpack(done,
  total)` for a progress bar; the event loop runs between samples), keep
  that SF2 (`entry.sha256`) and the SHA-256 of the SF3
  (`entry.originalSha256`: `sameFile` and a second import find it). A
  source's `size` and `sha256` are those of the SF3 (`compressed: true`).
  `midiSoundFontIsCompressed(bytes)` tells one; the synth never sees one.
* On the web, decompress in a web worker:
  `MidiSoundFontLibrary(..., decompress: midiSoundFontWorkerDecompressor())`
  (io: in the calling isolate), the script `sound_font_worker.js` built next
  to the page before a web build (`dart run
  milomedy_sound_fonts:setup_sound_font_worker`, or
  `setupMidiSoundFontWorker()` of `package:milomedy_sound_fonts/setup.dart`
  from a tool; git ignore it). Missing, the SF3 is decompressed in the page
  (a console warning). A worker failure (`MidiSoundFontWorkerException`)
  keeps the downloaded file for the next try.
* Better than unpacking: keep the SF3 and play it per song.
  `MidiSoundFontLibrary(..., keepCompressed: true)` stores a downloaded or
  imported SF3 as it is (`entry.compressed`, `read` gives the SF3,
  `presets(id)` reads the presets without decoding; an SF2 stays an SF2, an
  SF3 unpacked before is found again, and `replaceUnpacked(source)`
  downloads it again in its place: the same id, its SF2 deleted). Then, for
  the session,
  `var sampler = await midiSoundFontSampler(await library.read(id))` (a web
  worker of its own on the web, the bytes moved to it; io: here), and for
  each song `sampler.soundFont(sampler.samplesOf(timeline, margin: 12))`:
  an SF2 with the whole definition and that song's samples only (1 to 3 MB
  for GeneralUser GS instead of 32), given to the engine with
  `loadSoundFont(id, bytes, transfer: true)`. `samplesOf` follows the bank
  and program changes of the timeline as the synth does; `margin` covers
  the transpositions offered (an instrument chosen later needs its samples
  added: call it again and load the union). Never decode an SF3 in the
  AudioWorklet: the sampler does it in its worker.
* A catalog lists the SF3 sources apart (`"compressedSoundFonts": [...]`,
  read first): an app built before SF3 reads `soundFonts` only and never
  offers one. `sameAs` (an id) links the SF2 and the SF3 of the same bank
  (`midiGeneralUserGs` and `midiGeneralUserGsSf3`): offer the first listed,
  and neither once one is installed.
* Making an SF3 (io): `midiSoundFontCompress(sf2, encode:
  midiFfmpegVorbisEncoder(quality: 6))` of
  `package:milomedy_sound_fonts/sf3_ffmpeg.dart` (ffmpeg with libvorbis on
  the PATH, the same bytes for the same input), or
  `dart run tool/compress_sound_font.dart in.sf2 out.sf3 --quality 6`, which
  checks frames and loops (`midiSoundFontSampleDifferences`) and prints the
  signal to noise ratios (`midiSoundFontSampleSnr`).
* Licences: show `entry.copyright` and `entry.comments` of an imported
  SoundFont, `entry.licence` of a downloaded one.
* `delete(id)` removes the file and the entry (not the built-in one, an
  `ArgumentError`); the default goes back to `'tiny'`.
* Testing: `newFileSystemMemory()` of `package:fs_shim/fs_memory.dart` and a
  `MockClient` of `package:http/testing.dart`; `midiTinySoundFontBytes()` of
  milomedy_midi_synth_sf2 is a valid SoundFont (already in the library as the
  built-in one: change its name bytes for another one);
  `midiTinySoundFontSf3Bytes()` is the same in SF3.

## Examples

### The default SoundFont on first use

```dart
import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';

/// One library per folder in the app.
final library = MidiSoundFontLibrary(
  fileSystem: fileSystemDefault,
  path: 'sound_fonts',
);

/// The bytes of the default SoundFont, GeneralUser GS downloaded from
/// [hostedCopy] the first time; the built-in one when offline.
Future<Uint8List> defaultSoundFont(Uri hostedCopy) async {
  try {
    var entry = await library.ensure(midiGeneralUserGs(url: hostedCopy));
    await library.setDefault(entry.id);
  } on Exception catch (e) {
    print('download failed: $e'); // offline: the default stays
  }
  return library.read(await library.defaultId());
}
```

### A test with a memory file system and a mocked download

```dart
import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

void main() {
  test('a download that is not a SoundFont is refused', () async {
    var bytes = Uint8List(100); // not a .sf2 file
    var requests = 0;
    var library = MidiSoundFontLibrary(
      fileSystem: newFileSystemMemory(),
      path: 'sf',
      client: MockClient((request) async {
        requests++;
        return http.Response.bytes(bytes, 200);
      }),
    );
    var source = MidiSoundFontSource(
      id: 'my_font',
      name: 'My font',
      url: Uri.parse('https://example.com/my_font.sf2'),
      licence: 'Test only',
    );
    await expectLater(library.ensure(source), throwsA(anything));
    expect(requests, 1);
    // Nothing added: the built-in one only.
    expect((await library.list()).single.id, MidiSoundFontLibrary.builtInId);
  });
}
```
