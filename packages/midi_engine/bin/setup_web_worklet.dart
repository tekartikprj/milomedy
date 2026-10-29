import 'package:milomedy_midi_engine/setup.dart';

/// Builds the AudioWorklet module of milomedy_midi_engine from Dart (dart2js)
/// and writes it next to the page, when the Dart SDK or a package of the
/// worklet changed since the last build:
/// `dart run milomedy_midi_engine:setup_web_worklet [--dir web] [-f] [-v] [<app path>]`.
Future<void> main(List<String> arguments) => setupMidiWebWorkletMain(arguments);
