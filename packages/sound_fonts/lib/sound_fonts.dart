/// The SoundFont library of the MIDI engine: [MidiSoundFontLibrary] keeps
/// the SoundFonts downloaded ([MidiSoundFontSource], [midiGeneralUserGs]) or
/// imported, through fs_shim, with the default one and a built-in fallback;
/// [MidiSoundFontCatalog] lists the SoundFonts an app offers and where.
library;

import 'src/catalog.dart';
import 'src/library.dart';
import 'src/source.dart';

export 'src/catalog.dart';
export 'src/library.dart';
export 'src/source.dart';
