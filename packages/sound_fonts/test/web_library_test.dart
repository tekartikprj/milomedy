@TestOn('browser')
library;

import 'package:fs_shim/fs_browser.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/sound_fonts.dart';

void main() {
  test('kept in IndexedDB', () async {
    var fileSystem = newFileSystemWeb(name: 'milomedy_sound_fonts_test');
    var library = MidiSoundFontLibrary(fileSystem: fileSystem, path: 'sf');
    var copy = copySoundFontBytes();
    var entry = await library.import(copy);
    await library.setDefault(entry.id);
    // Another library on the same database.
    var again = MidiSoundFontLibrary(
      fileSystem: newFileSystemWeb(name: 'milomedy_sound_fonts_test'),
      path: 'sf',
    );
    expect(await again.defaultId(), entry.id);
    expect(await again.read(entry.id), copy);
    await again.delete(entry.id);
    expect(await again.list(), hasLength(1));
  });
}
