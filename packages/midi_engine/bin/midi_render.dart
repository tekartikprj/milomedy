// ignore_for_file: avoid_print

import 'dart:io';

import 'package:tekartik_midi_engine/midi_engine.dart';
import 'package:tekartik_midi_synth/midi_synth.dart';

const _usage = '''
Renders a MIDI file to a 16-bit stereo WAV file.

Usage: dart run tekartik_midi_engine:midi_render [options] <file.mid>

Options:
  -o <file.wav>     the output (the input with .wav by default)
  --rate <hz>       the sample rate (44100)
  --speed <factor>  the speed (1)
  --transpose <n>   the transposition in semitones (0)

Until the SoundFont synth: every program plays the accordion reed, the
percussion channel the metronome click.''';

Future<void> main(List<String> arguments) async {
  String? input;
  String? output;
  var sampleRate = 44100;
  var speed = 1.0;
  var transpose = 0;
  try {
    for (var i = 0; i < arguments.length; i++) {
      var argument = arguments[i];
      String value() {
        if (i + 1 >= arguments.length) {
          throw FormatException('$argument needs a value');
        }
        return arguments[++i];
      }

      switch (argument) {
        case '-h' || '--help':
          print(_usage);
          return;
        case '-o':
          output = value();
        case '--rate':
          sampleRate = int.parse(value());
        case '--speed':
          speed = double.parse(value());
        case '--transpose':
          transpose = int.parse(value());
        default:
          if (argument.startsWith('-') || input != null) {
            throw FormatException('unexpected $argument');
          }
          input = argument;
      }
    }
    if (input == null) {
      throw const FormatException('no MIDI file');
    }
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exitCode = 64;
    return;
  }

  MidiSong song;
  try {
    song = MidiSong.fromBytes(await File(input).readAsBytes());
  } on FileSystemException catch (e) {
    stderr.writeln('$input: ${e.osError?.message ?? e.message}');
    exitCode = 66;
    return;
  } on Object catch (e) {
    // A file that is not MIDI, or format 2.
    stderr.writeln('$input: $e');
    exitCode = 65;
    return;
  }
  var engine =
      MidiEngine(
          sampleRate: sampleRate,
          synths: [
            DartSynth(
              sampleRate: sampleRate,
              instrument: ReedInstrument.treble(),
              percussion: const ClickInstrument(),
            ),
          ],
        )
        ..speed = speed
        ..transpose = transpose;
  var stopwatch = Stopwatch()..start();
  var samples = midiRenderOffline(engine, song.toTimeline());
  var elapsed = stopwatch.elapsedMilliseconds;
  output ??= '${input.replaceFirst(RegExp(r'\.(mid|midi|kar)$'), '')}.wav';
  await File(
    output,
  ).writeAsBytes(midiWavBytes(samples, sampleRate: sampleRate));
  var seconds = samples.length / 2 / sampleRate;
  print(
    '$output: ${song.notes.length} notes, ${seconds.toStringAsFixed(1)} s '
    'rendered in $elapsed ms',
  );
}
