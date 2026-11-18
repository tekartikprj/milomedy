/// What each song asks of a SoundFont played per song
/// (`MidiSoundFontSampler`): the samples it plays, their frames, the
/// SoundFont made for it and the time to make it (its samples decoded),
/// with a margin for transposing; each note checked against the synth's
/// own lookup.
///
/// ```sh
/// dart run tool/song_samples.dart GeneralUser-GS.sf3 song.mid songs/
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:path/path.dart';

/// The transpositions the app offers, up and down.
const _margin = 12;

String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(2);

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'usage: song_samples.dart <soundfont.sf2|sf3> <song.mid|folder>...',
    );
    exitCode = 64;
    return;
  }
  var bytes = File(arguments.first).readAsBytesSync();
  var sampler = MidiSoundFontLocalSampler(bytes, cacheBytes: 0);
  var definition = sampler.definition;
  // The synth's lookup, on the SF2 (an SF3 decompressed first).
  var sf2 = await midiSoundFontDecompress(bytes);
  var melty = MidiSoundFont.fromBytes(sf2);
  stdout.writeln(
    '${definition.name}: ${definition.presets.length} presets, '
    '${definition.samples.length} samples, ${_mb(bytes.length)} MB, '
    '${_mb(sf2.length)} MB as SF2',
  );
  var songs = <File>[
    for (var path in arguments.skip(1))
      if (FileSystemEntity.isDirectorySync(path))
        ...Directory(path).listSync().whereType<File>().where(
          (file) => const [
            '.mid',
            '.midi',
            '.kar',
          ].contains(extension(file.path).toLowerCase()),
        )
      else
        File(path),
  ]..sort((a, b) => a.path.compareTo(b.path));

  var mismatches = 0;
  var rows = <(String, int, int, int, int, int)>[];
  for (var file in songs) {
    MidiTimeline timeline;
    try {
      timeline = MidiSong.fromBytes(
        file.readAsBytesSync(),
      ).toTimeline(trackOf: (_, channel) => channel);
    } on FormatException catch (e) {
      stdout.writeln('${basename(file.path)}: not read ($e)');
      continue;
    }
    var notes = midiSoundFontNotes(timeline);
    var samples = definition.samplesFor(notes);
    for (var note in notes) {
      var found = definition.samplesFor([note]);
      var expected = _meltySamples(melty, note);
      if (found.length != expected.length || !found.containsAll(expected)) {
        mismatches++;
      }
    }
    var margin = sampler.samplesOf(timeline, margin: _margin);
    var watch = Stopwatch()..start();
    var made = await sampler.soundFont(samples);
    var elapsed = watch.elapsedMilliseconds;
    rows.add((
      basename(file.path),
      samples.length,
      _frameBytes(sf2, samples),
      margin.length,
      made.length,
      elapsed,
    ));
  }
  stdout.writeln(
    'song: samples, their frames (MB), with ±$_margin semitones, '
    'the SoundFont made (MB), made in (ms)',
  );
  for (var (name, count, frames, margin, made, ms) in rows) {
    stdout.writeln('$name: $count, ${_mb(frames)}, $margin, ${_mb(made)}, $ms');
  }
  if (rows.isNotEmpty) {
    List<int> sorted(int Function((String, int, int, int, int, int)) of) =>
        rows.map(of).toList()..sort();
    String range(List<int> values, String Function(int) show) =>
        '${show(values.first)} to ${show(values.last)}, '
        'median ${show(values[values.length ~/ 2])}';
    stdout
      ..writeln('${rows.length} songs')
      ..writeln('samples: ${range(sorted((r) => r.$2), (v) => '$v')}')
      ..writeln('frames (MB): ${range(sorted((r) => r.$3), _mb)}')
      ..writeln('±$_margin: ${range(sorted((r) => r.$4), (v) => '$v')}')
      ..writeln('SoundFont (MB): ${range(sorted((r) => r.$5), _mb)}')
      ..writeln('made in (ms): ${range(sorted((r) => r.$6), (v) => '$v')}');
  }
  stdout.writeln(
    mismatches == 0
        ? 'every note: the samples the synth plays'
        : '$mismatches notes found other samples than the synth',
  );
  if (mismatches > 0) {
    exitCode = 1;
  }
}

/// The bytes of the 16-bit frames of [samples] in the SF2 [sf2].
int _frameBytes(Uint8List sf2, Set<int> samples) {
  var headers = MidiSoundFontDefinition.fromBytes(sf2).samples;
  return samples.fold(
    0,
    (bytes, i) => bytes + (headers[i].end - headers[i].start) * 2,
  );
}

/// The samples dart_melty_soundfont plays for [note] (`Synthesizer.noteOn`).
Set<int> _meltySamples(MidiSoundFont soundFont, MidiSoundFontNote note) {
  var melty = soundFont.soundFont;
  var lookup = {
    for (var preset in melty.presets)
      preset.bankNumber << 16 | preset.patchNumber: preset,
  };
  var lowestId = lookup.keys.reduce((a, b) => a < b ? a : b);
  var lowest = melty.presets.firstWhere(
    (preset) => (preset.bankNumber << 16 | preset.patchNumber) == lowestId,
  );
  var preset =
      lookup[note.bank << 16 | note.program] ??
      lookup[note.bank < 128 ? note.program : 128 << 16] ??
      lowest;
  return {
    for (var presetRegion in preset.regions)
      if (presetRegion.contains(note.key, note.velocity))
        for (var region in presetRegion.instrument.regions)
          if (region.contains(note.key, note.velocity))
            melty.sampleHeaders.indexWhere(
              (sample) => identical(sample, region.sample),
            ),
  };
}
