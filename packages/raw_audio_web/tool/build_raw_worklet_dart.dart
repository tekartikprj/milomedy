import 'dart:io';

/// Compiles the processor of example/raw_worklet_dart with dart2js: its
/// output is the AudioWorklet module as it is (build_runner's development
/// compiler, DDC, cannot make one).
Future<void> main() async {
  var result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O2',
    '--no-source-maps',
    '-o',
    'example/raw_worklet_dart/processor.js',
    'example/raw_worklet_dart/processor.dart',
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
