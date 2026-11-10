// ignore_for_file: avoid_print

import 'package:fs_shim/fs_shim.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';

/// Lists the SoundFonts of a library, after importing the .sf2 files given
/// (`dart run example/main.dart my_font.sf2`).
///
/// In memory here: `fileSystemDefault` keeps them (files on io, IndexedDB
/// on the web).
Future<void> main(List<String> arguments) async {
  var library = MidiSoundFontLibrary(
    fileSystem: fileSystemMemory,
    path: 'sound_fonts',
  );
  for (var path in arguments) {
    var entry = await library.import(
      await fileSystemIo.file(path).readAsBytes(),
    );
    await library.setDefault(entry.id);
  }
  print('default: ${await library.defaultId()}');
  for (var entry in await library.list()) {
    print(
      '${entry.id}: ${entry.name}, ${entry.presetCount} presets, '
      '${entry.size} bytes${entry.builtIn ? ' (built in)' : ''}',
    );
    if (entry.copyright.isNotEmpty) {
      print('  ${entry.copyright}');
    }
  }
}
