import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:wav/wav.dart';

/// The frequencies of the C major scale, from C4 to C5.
const _scale = [261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88, 523.25];

/// A C major scale of sine tones, played again until [seconds] are filled.
Float64List exampleScale({required int seconds, required int sampleRate}) {
  var samples = Float64List(seconds * sampleRate);
  var noteFrames = (0.375 * sampleRate).round();
  var fadeFrames = (0.01 * sampleRate).round();
  for (var i = 0; i < samples.length; i++) {
    var frequency = _scale[(i ~/ noteFrames) % _scale.length];
    var inNote = i % noteFrames;
    // A short fade in and out, so the notes do not click.
    var fade = math.min(
      1.0,
      math.min(inNote, noteFrames - 1 - inNote) / fadeFrames,
    );
    samples[i] =
        0.3 * fade * math.sin(2 * math.pi * frequency * i / sampleRate);
  }
  return samples;
}

/// The wav file the examples play: [seconds] of the scale in stereo, written
/// once to `.local/` (no sample is shipped with the package).
Future<String> exampleWavPath({required int seconds}) async {
  var path = join('.local', 'example_scale_${seconds}s.wav');
  var file = File(path);
  if (!file.existsSync()) {
    await file.parent.create(recursive: true);
    const sampleRate = 44100;
    var channel = exampleScale(seconds: seconds, sampleRate: sampleRate);
    await Wav([channel, channel], sampleRate).writeFile(path);
  }
  return path;
}
