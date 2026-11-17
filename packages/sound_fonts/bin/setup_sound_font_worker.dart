import 'package:milomedy_sound_fonts/setup.dart';

/// Builds the SoundFont worker script of an app (`sound_font_worker.js`,
/// the SF3 decoder compiled with dart2js) and writes it next to its page,
/// when the Dart SDK or a package of the worker changed since the last
/// build: `dart run milomedy_sound_fonts:setup_sound_font_worker [--dir web]
/// [-f] [-v] [<app path>]`.
Future<void> main(List<String> arguments) =>
    midiSoundFontWorkerScript.setupMain(
      arguments,
      command: 'dart run milomedy_sound_fonts:setup_sound_font_worker',
    );
