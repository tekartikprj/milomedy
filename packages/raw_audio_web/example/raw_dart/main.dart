import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tekartik_test_menu_browser/test_menu_web.dart';
import 'package:web/web.dart' hide Float32List;

var audioContext = AudioContext();

/// The frequencies of the C major scale, from C4 to C5.
const _scale = [261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88, 523.25];

/// [seconds] of a C major scale of sine tones, made here (no file to load).
AudioBuffer exampleAudioBuffer({required int seconds}) {
  var sampleRate = audioContext.sampleRate;
  var samples = Float32List((seconds * sampleRate).round());
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
  return audioContext.createBuffer(1, samples.length, sampleRate)
    ..copyToChannel(samples.toJS, 0);
}

Future<void> streamAudio(AudioBuffer buffer, int chunkSize) async {
  final int numChunks = (buffer.length / chunkSize).ceil();

  /// 250ms latency
  var startTime = audioContext.currentTime + .250;
  write('info ${{'now': '${audioContext.currentTime}'}}');
  for (int i = 0; i < numChunks; i++) {
    final int start = i * chunkSize;
    final int end = (i + 1) * chunkSize;

    // Create a new AudioBufferSourceNode for each chunk
    final AudioBufferSourceNode sourceNode = audioContext.createBufferSource();

    // Create a new AudioBuffer for the chunk
    final AudioBuffer chunkBuffer = audioContext.createBuffer(
      buffer.numberOfChannels,
      end - start,
      buffer.sampleRate,
    );

    // Copy the chunk data to the new buffer
    for (int channel = 0; channel < buffer.numberOfChannels; channel++) {
      chunkBuffer.copyToChannel(
        buffer.getChannelData(channel).toDart.sublist(start, end).toJS,
        channel,
      );
    }

    write('streaming $start to $end');
    sourceNode.buffer = chunkBuffer;
    sourceNode.connect(audioContext.destination);
    var map = {'startTime': startTime, 'before': audioContext.currentTime};
    sourceNode.start(startTime);

    startTime += chunkBuffer.duration;

    var completer = Completer();

    sourceNode.onEnded.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    // Adjust the delay between chunks as needed
    // await Future.delayed(Duration(milliseconds: 1000));
    await completer.future;
    map['after'] = audioContext.currentTime;
    write('info $map');
  }
}

void main() {
  mainMenuWeb(() {
    item('play 3s', () async {
      final audioBuffer = exampleAudioBuffer(seconds: 3);

      // Create a buffer source and connect it to the audio context
      final source = audioContext.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(audioContext.destination);

      // Play the audio
      source.start();
    });

    item('play 60s', () async {
      final audioBuffer = exampleAudioBuffer(seconds: 60);

      await streamAudio(audioBuffer, 40000);
    });
  });
}
