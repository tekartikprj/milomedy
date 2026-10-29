import 'dart:io';

import 'package:dev_build/shell.dart';
import 'package:path/path.dart';

Future<void> main(List<String> args) async {
  var dir = Directory(join('.local', 'portaudioref'));
  await dir.create(recursive: true);
  var shell = Shell(workingDirectory: dir.path);
  await shell.run('scclone https://github.com/PortAudio/portaudio .');
}
