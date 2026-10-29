// ignore_for_file: avoid_print

import 'dart:io';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

/// The real-time factor of the SoundFont synth: renders a MIDI file with a
/// SoundFont (reverb and chorus on), as fast as possible, in blocks of 128
/// frames (an AudioWorklet's) and of 2048.
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
  for (var block in [128, 2048]) {
    var engine = MidiEngine(
      sampleRate: 44100,
      synths: [MidiSoundFontSynth(soundFont)],
    )..load(song.toTimeline());
    var total = (song.duration * 44100).round();
    var stopwatch = Stopwatch()..start();
    for (var done = 0; done < total; done += block) {
      engine.render(block);
    }
    var seconds = stopwatch.elapsedMicroseconds / 1e6;
    print(
      'blocks of $block: ${(song.duration / seconds).toStringAsFixed(1)}x '
      'real time (${seconds.toStringAsFixed(2)} s)',
    );
  }
}
