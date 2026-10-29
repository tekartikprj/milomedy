/// The output of the engine on mp_audio_stream (io): a [MidiPcmStream] of
/// interleaved stereo frames.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:mp_audio_stream/mp_audio_stream.dart';

/// A [MidiPcmStream] on mp_audio_stream: miniaudio, bundled in the plugin.
///
/// It has a single native stream: open one at a time, and push from one
/// isolate only (the player's).
class MidiMpAudioStream implements MidiPcmStream {
  final AudioStream _stream;

  /// Opens the stream at [sampleRate], its buffer of [bufferSeconds] (more
  /// than what the player pushes ahead), playing again after running out
  /// once [waitingSeconds] are buffered.
  MidiMpAudioStream.open({
    required int sampleRate,
    double bufferSeconds = 0.5,
    double waitingSeconds = 0.02,
  }) : _stream = getAudioStream() {
    var result = _stream.init(
      bufferMilliSec: (bufferSeconds * 1000).round(),
      waitingBufferMilliSec: (waitingSeconds * 1000).round(),
      channels: 2,
      sampleRate: sampleRate,
      fadeOnExhaust: true,
    );
    if (result != 0) {
      throw StateError('mp_audio_stream init failed ($result)');
    }
    _stream.resume();
  }

  @override
  bool push(Float32List frames) => _stream.push(frames) == 0;

  @override
  int get exhaustCount => _stream.stat().exhaust;

  @override
  void close() => _stream.uninit();
}

/// Opens a [MidiMpAudioStream] at [sampleRate]: the opener of the isolate
/// player.
MidiPcmStream midiMpAudioStreamOpener(int sampleRate) =>
    MidiMpAudioStream.open(sampleRate: sampleRate);
