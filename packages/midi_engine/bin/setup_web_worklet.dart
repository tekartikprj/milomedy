import 'dart:io';

import 'package:milomedy_midi_engine/setup.dart';

const _usage = '''
Builds the AudioWorklet module of milomedy_midi_engine from Dart (dart2js)
and writes it next to the page, when the package, its sources, the web
package or the Dart SDK changed since the last build.

Usage: dart run milomedy_midi_engine:setup_web_worklet [options] [<app path>]

Options:
  --dir <dir>     the folder of the page in the app (web)
  -f, --force     build again whatever the cache says
  -v, --verbose   tell what is done''';

Future<void> main(List<String> arguments) async {
  String? path;
  var dir = 'web';
  var force = false;
  var verbose = false;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      case '--dir' when i + 1 < arguments.length:
        dir = arguments[++i];
      case '-f' || '--force':
        force = true;
      case '-v' || '--verbose':
        verbose = true;
      case var argument when !argument.startsWith('-') && path == null:
        path = argument;
      case var argument:
        stderr.writeln('unexpected $argument\n\n$_usage');
        exitCode = 64;
        return;
    }
  }
  await setupMidiWebWorklet(
    path: path,
    dir: dir,
    force: force,
    verbose: verbose,
  );
}
