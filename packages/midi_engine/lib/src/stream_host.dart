/// An engine host on a raw audio stream (mp_audio_stream on io), fed from a
/// timer of its isolate: the blocks are rendered when asked and pushed a
/// little ahead of the stream's clock; silence when nothing plays, so that
/// the stream never runs out and its clock stays right.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'host.dart';
import 'protocol.dart';
import 'stream_sink.dart';
import 'synth_spec.dart';

/// The host.
class MidiStreamHost {
  /// The stream.
  final MidiPcmStream stream;

  /// The sample rate.
  final int sampleRate;

  /// How far ahead of the clock the frames are pushed, in seconds: the delay
  /// before a command is heard.
  final double latency;

  /// The frames of a block rendered and pushed.
  final int blockFrames;

  /// Sends an event to the player.
  final void Function(Map<String, Object?> event) send;

  /// The clock, set by hand when given (the tests).
  final double Function()? clock;

  /// The engine host.
  late final MidiEngineHost host;

  final _stopwatch = Stopwatch();

  /// Added to the stopwatch: the stream played faster than it.
  var _offset = 0.0;

  /// The frame of the stream's clock pushed next.
  var _written = 0;

  var _exhaustCount = 0;

  /// A block rendered but not pushed yet (the stream was full).
  Float32List? _pending;

  final Float32List _left;
  final Float32List _right;

  /// A host of the synths of [synths] on [stream] at [sampleRate].
  MidiStreamHost({
    required this.stream,
    required this.sampleRate,
    required List<MidiSynthSpec> synths,
    required this.send,
    this.latency = 0.1,
    this.blockFrames = 256,
    this.clock,
  }) : _left = Float32List(blockFrames),
       _right = Float32List(blockFrames) {
    host = MidiEngineHost(
      sampleRate: sampleRate,
      synths: synths,
      send: _onHostEvent,
    );
    _exhaustCount = stream.exhaustCount;
  }

  /// The stream's clock, in seconds.
  double get currentTime =>
      (clock?.call() ?? _stopwatch.elapsedMicroseconds / 1e6) + _offset;

  int get _nowFrame => (currentTime * sampleRate).floor();

  /// The position events give the position heard when sent: the host
  /// reports the blocks it renders, heard [latency] later.
  void _onHostEvent(Map<String, Object?> event) {
    if (event['type'] == MidiHostEvents.position) {
      var speed = event['speed']! as double;
      var heard =
          (event['position']! as double) +
          (currentTime - (event['time']! as double)) * speed;
      send({...event, 'position': heard}..remove('time'));
    } else {
      send(event);
    }
  }

  /// Handles a command.
  void handle(Map<Object?, Object?> command) => host.handle(command);

  /// Pushes the frames up to [latency] ahead of the clock: called every few
  /// milliseconds.
  void feed() {
    _stopwatch.start();
    var now = _nowFrame;
    if (stream.exhaustCount != _exhaustCount) {
      _exhaustCount = stream.exhaustCount;
      if (_written > now) {
        // The stream played everything pushed: its clock is ahead.
        _offset += (_written - now) / sampleRate;
        now = _written;
      }
    }
    if (_written < now) {
      // Late: what is pushed now plays now.
      _written = now;
    }
    var latencyFrames = (latency * sampleRate).round();
    while (_written < now + latencyFrames) {
      var block = _pending ?? _render();
      if (!stream.push(block)) {
        _pending = block;
        break;
      }
      _pending = null;
      _written += blockFrames;
    }
    // Counted after pushing: the stream also counts the callbacks it waits
    // through for the first frames.
    _exhaustCount = stream.exhaustCount;
  }

  /// The next block, interleaved stereo.
  Float32List _render() {
    host.render(_left, _right, _written / sampleRate);
    var frames = Float32List(blockFrames * 2);
    for (var i = 0; i < blockFrames; i++) {
      frames[2 * i] = _left[i];
      frames[2 * i + 1] = _right[i];
    }
    return frames;
  }

  /// The frames pushed ahead of the clock, in seconds.
  double get ahead => math.max(0, _written / sampleRate - currentTime);
}
