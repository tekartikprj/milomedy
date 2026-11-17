/// The setup of an app on the web (dart:io, run from a tool): builds the
/// SoundFont worker script (`sound_font_worker.js`, the SF3 decoder
/// compiled with dart2js) that `midiSoundFontWorkerDecompressor` runs.
library;

import 'package:tekartik_web_worker_build/web_worker_build.dart';

import 'src/worker/protocol.dart';

export 'package:tekartik_web_worker_build/web_worker_build.dart'
    show WebWorkerScriptSetupResult;
export 'src/worker/protocol.dart' show midiSoundFontWorkerJsFilename;

const _package = 'milomedy_sound_fonts';

/// The worker script: `sound_font_worker.js`.
const midiSoundFontWorkerScript = WebWorkerScript(
  package: _package,
  filename: midiSoundFontWorkerJsFilename,
  entry: 'package:$_package/src/worker/worker_main.dart',
  output: _output,
);

String _output(String js, ProjectPackages packages) =>
    '''
// SoundFont worker of $_package ${packages.version(_package)}, built by
// `dart run $_package:setup_sound_font_worker`. Do not edit.
$js''';

/// Builds `sound_font_worker.js` for the app at [path] (the current
/// directory by default) when needed (a new Dart SDK, a package of the
/// worker changed), and writes it as [filename] in its [dir] folder
/// (`web`), next to the page.
Future<WebWorkerScriptSetupResult> setupMidiSoundFontWorker({
  String? path,
  String dir = 'web',
  String? filename,
  bool force = false,
  bool verbose = false,
}) => midiSoundFontWorkerScript.setup(
  path: path,
  dir: dir,
  filename: filename,
  force: force,
  verbose: verbose,
);
