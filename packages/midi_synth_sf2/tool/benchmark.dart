// ignore_for_file: avoid_print

import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

import 'benchmark_lines.dart';

/// The real-time factor of the SoundFont synth: renders a MIDI file with a
/// SoundFont, as fast as possible:
///
/// - one synth, reverb and chorus on, in blocks of 128 frames (an
///   AudioWorklet's) and of 2048;
/// - one track per channel (an app's mixer), in blocks of 128 frames mixed
///   as the hosts do (`MidiStereoMixdown`): 16 synths with their reverb and
///   chorus, 16 dry synths, then 16 dry synths sending to the shared reverb
///   (the CC 91 of the file, 40 when none).
///
/// `dart run tool/benchmark.dart <file.sf2> <file.mid>`, or compiled with
/// `dart compile exe tool/benchmark.dart`.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: benchmark <file.sf2> <file.mid>');
    exitCode = 64;
    return;
  }
  var loading = Stopwatch()..start();
  var soundFont = MidiSoundFont.fromBytes(
    await File(arguments[0]).readAsBytes(),
  );
  var song = MidiSong.fromBytes(await File(arguments[1]).readAsBytes());
  print(
    '${soundFont.name}: ${soundFont.presets.length} presets, loaded in '
    '${loading.elapsedMilliseconds} ms; ${song.notes.length} notes, '
    '${song.duration.toStringAsFixed(1)} s',
  );
  for (var line in midiBenchmark(soundFont, song)) {
    print(line);
  }
}
