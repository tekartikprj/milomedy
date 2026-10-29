import 'dart:math' as math;

import 'package:tekartik_raw_audio/raw_audio.dart';

/// generate a sine wave (pcm16)
List<int> _pcm16GenerateSineWave({
  int periods = 1,
  int sampleRate = 44100,
  double freq = 440,
  double volume = 0.5,
}) {
  final nFramesPerPeriod = (sampleRate / freq).toInt();
  final totalFrames = nFramesPerPeriod * periods;
  final step = math.pi * 2 / nFramesPerPeriod;
  var data = List.generate(totalFrames, (i) {
    return (math.sin(step * (i % nFramesPerPeriod)) * volume * 32767).toInt();
  });
  return data;
}

/// generate a sine wave (pcm16)
RawAudioData pcm16GenerateSineWaveAudioData({
  int periods = 1,
  int sampleRate = 44100,
  double freq = 440,
  double volume = 0.5,
}) {
  return RawAudioData.fromInt16List(
    _pcm16GenerateSineWave(
      periods: periods,
      sampleRate: sampleRate,
      freq: freq,
      volume: volume,
    ),
  );
}

/// Generate example audio data
RawAudioData pcm16GenerateExampleAudioData({
  int sampleRate = 44100,
  double volume = 0.5,
  double noteDuration = 0.5,
  List<double> freqs = const [
    261.63,
    294.33,
    327.03,
    348.83,
    392.44,
    436.05,
    490.55,
    523.25,
  ],
}) {
  var data = <int>[];
  for (var freq in freqs) {
    var periodsPerSecond = freq;
    var periods = (noteDuration * periodsPerSecond).round();
    data += _pcm16GenerateSineWave(
      periods: periods,
      sampleRate: sampleRate,
      freq: freq,
      volume: volume,
    );
  }
  return RawAudioData.fromInt16List(data);
}
