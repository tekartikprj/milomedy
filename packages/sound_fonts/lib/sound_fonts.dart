/// The SoundFont library of the MIDI engine: [MidiSoundFontLibrary] keeps
/// the SoundFonts downloaded ([MidiSoundFontSource], [midiGeneralUserGs]) or
/// imported, through fs_shim, with the default one and a built-in fallback;
/// [MidiSoundFontCatalog] lists the SoundFonts an app offers and where;
/// [midiSoundFontDecompress] turns an SF3 (compressed samples) into an SF2.
library;

import 'src/catalog.dart';
import 'src/library.dart';
import 'src/sf3.dart';
import 'src/source.dart';

export 'src/catalog.dart';
export 'src/library.dart';
export 'src/sf3.dart';
export 'src/source.dart';
export 'src/tiny_sf3.dart';
export 'src/worker/decompressor.dart';
