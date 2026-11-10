---
name: milomedy-sound-fonts
description: >-
  Use when an app keeps SoundFonts (.sf2) for the milomedy MIDI engine with
  milomedy_sound_fonts: MidiSoundFontLibrary (list, entry, read, import,
  download, ensure, setDefault, defaultId, delete) on an fs_shim file system
  (files on io, IndexedDB on the web), MidiSoundFontSource and its size and
  git blob checks, midiGeneralUserGs (a hosted copy, its licence), the
  built-in 'tiny' fallback, and testing with a memory file system and an
  http MockClient.
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
* `download(source, onProgress:)` throws `MidiSoundFontDownloadException` on
  a non 200 answer, a wrong size or a wrong git blob id (when the source
  gives them); nothing is added then. The whole file is kept in memory until
  checked.
* `ensure(source)` returns the entry of `source.id`, or the same file
  imported under another id (found without downloading when the source gives
  `size` and `gitBlobSha1`), or downloads it.
* GeneralUser GS (`midiGeneralUserGs(url: hostedCopy)`): its licence asks not
  to link to the author's download files, so the app hosts a copy;
  `midiGeneralUserGsUpstreamUrl` is for development and tools only.
* Licences: show `entry.copyright` and `entry.comments` of an imported
  SoundFont, `entry.licence` of a downloaded one.
* `delete(id)` removes the file and the entry (not the built-in one, an
  `ArgumentError`); the default goes back to `'tiny'`.
* Testing: `newFileSystemMemory()` of `package:fs_shim/fs_memory.dart` and a
  `MockClient` of `package:http/testing.dart`; `midiTinySoundFontBytes()` of
  milomedy_midi_synth_sf2 is a valid SoundFont (already in the library as the
  built-in one: change its name bytes for another one).

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
