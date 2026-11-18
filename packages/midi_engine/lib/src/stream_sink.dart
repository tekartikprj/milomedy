/// An output on a raw audio stream (mp_audio_stream on the desktop): the
/// blocks scheduled are kept by their time, mixed with the gain and pan of
/// each track and pushed a little ahead of the clock, chunk by chunk, so
/// that a change (a volume, a seek) is heard after that little only.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'chorus.dart';
import 'engine.dart';
import 'mixer.dart';
import 'reverb.dart';
import 'sink.dart';

/// A raw audio stream: plays the frames pushed one after the other at its
/// own pace, silence when it runs out of them.
abstract class MidiPcmStream {
  /// Pushes interleaved stereo frames; false when its buffer is full (the
  /// frames are dropped).
  bool push(Float32List frames);

  /// How many times it ran out of frames (to follow its clock).
  int get exhaustCount;

  /// Closes the stream.
  void close();
}

/// A block scheduled, by frame of the output clock.
class _Queued {
  final int start;
  final MidiRenderBlock block;

  _Queued(this.start, this.block);

  int get end => start + block.frames;
}

/// The mix of a track: its gain (and its effect sends) moves to [target]
/// over a chunk.
class _TrackMix {
  double gain;
  double target;
  double pan;
  var reverb = 0.0;
  var reverbTarget = 0.0;
  var chorus = 0.0;
  var chorusTarget = 0.0;

  _TrackMix(this.gain, this.pan) : target = gain;
}

/// An output on a raw stream: its clock is a stopwatch (the stream plays in
/// real time), the frames pushed run [latency] ahead of it.
class MidiStreamSink implements MidiAudioSink, MidiReverbSink, MidiChorusSink {
  /// The stream.
  final MidiPcmStream stream;

  @override
  final int sampleRate;

  /// How far ahead of the clock the frames are pushed, in seconds: the
  /// delay before a change is heard.
  final double latency;

  /// The frames of a chunk pushed.
  final int chunkFrames;

  /// The clock, set by hand when given (the tests).
  final double Function()? clock;

  final _stopwatch = Stopwatch();

  /// Added to the stopwatch: the stream played faster than it.
  var _offset = 0.0;

  final _queue = <_Queued>[];

  /// The frame of the output clock pushed next.
  var _written = 0;

  /// The end of the last block pushed (silence pushed a little after it,
  /// then the stream may run out).
  var _lastEnd = 0;

  var _exhaustCount = 0;
  final _tracks = <_TrackMix>[];
  final MidiLimiter _limiter;
  MidiReverbBus? _reverb;
  var _reverbLevel = 1.0;
  MidiChorusBus? _chorus;
  var _chorusLevel = 1.0;
  Timer? _timer;
  var _feedPending = false;

  /// An output on [stream] at [sampleRate].
  MidiStreamSink(
    this.stream, {
    required this.sampleRate,
    this.latency = 0.1,
    this.chunkFrames = 256,
    this.clock,
  }) : _limiter = MidiLimiter(sampleRate: sampleRate) {
    _exhaustCount = stream.exhaustCount;
  }

  @override
  double get currentTime =>
      (clock?.call() ?? _stopwatch.elapsedMicroseconds / 1e6) + _offset;

  int get _nowFrame => (currentTime * sampleRate).floor();

  /// The frames pushed ahead of the clock.
  int get _latencyFrames => (latency * sampleRate).round();

  /// The output clock up to which frames were pushed, in seconds.
  double get pushedUntil => _written / sampleRate;

  @override
  double get startLatency =>
      math.max(0.04, (_written - _nowFrame) / sampleRate + 0.01);

  @override
  Future<void> resume() async {
    _stopwatch.start();
  }

  _TrackMix _track(int track) {
    while (_tracks.length <= track) {
      _tracks.add(_TrackMix(1, 0));
    }
    return _tracks[track];
  }

  @override
  void schedule(double when, MidiRenderBlock block) {
    var start = (when * sampleRate).round();
    // Contiguous with the previous block when it is, whatever the rounding.
    if (_queue.isNotEmpty && (start - _queue.last.end).abs() <= 2) {
      start = _queue.last.end;
    }
    _queue.add(_Queued(start, block));
    _lastEnd = math.max(_lastEnd, start + block.frames);
    _timer ??= Timer.periodic(const Duration(milliseconds: 10), (_) => feed());
    // Once the player has scheduled all its blocks: fed now, silence would
    // be pushed where its next block goes.
    if (!_feedPending) {
      _feedPending = true;
      scheduleMicrotask(() {
        _feedPending = false;
        if (_timer != null) {
          feed();
        }
      });
    }
  }

  @override
  void cancel() {
    // What was pushed plays out (at most [latency]).
    _queue.clear();
  }

  @override
  void setTrackMix(int track, {required double gain, required double pan}) {
    var isNew = track >= _tracks.length;
    var mix = _track(track)
      ..target = gain
      ..pan = pan;
    if (isNew) {
      mix.gain = gain;
    }
  }

  @override
  void setTrackReverb(int track, double send) {
    var isNew = track >= _tracks.length;
    var mix = _track(track)..reverbTarget = send;
    if (isNew) {
      mix.reverb = send;
    }
    if (send > 0) {
      _reverb ??= MidiReverbBus(sampleRate: sampleRate)..level = _reverbLevel;
    }
  }

  @override
  set reverbLevel(double level) {
    _reverbLevel = level;
    _reverb?.level = level;
  }

  @override
  void setTrackChorus(int track, double send) {
    var isNew = track >= _tracks.length;
    var mix = _track(track)..chorusTarget = send;
    if (isNew) {
      mix.chorus = send;
    }
    if (send > 0) {
      _chorus ??= MidiChorusBus(sampleRate: sampleRate)..level = _chorusLevel;
    }
  }

  @override
  set chorusLevel(double level) {
    _chorusLevel = level;
    _chorus?.level = level;
  }

  /// Pushes the frames up to [latency] ahead of the clock (called every
  /// 10 ms while there is something to play).
  void feed() {
    var now = _nowFrame;
    if (stream.exhaustCount != _exhaustCount) {
      if (_written > now) {
        // The stream played everything pushed: its clock is ahead.
        _offset += (_written - now) / sampleRate;
        now = _written;
      }
    }
    if (_written < now) {
      // Idle, or late: what is pushed now plays now.
      _written = now;
    }
    if (_queue.isEmpty && _written >= _lastEnd + _latencyFrames) {
      // Nothing to play: let the stream run out.
      _timer?.cancel();
      _timer = null;
      return;
    }
    while (_written < now + _latencyFrames) {
      var chunk = _mix(_written, chunkFrames);
      if (!stream.push(chunk)) {
        break;
      }
      _written += chunkFrames;
    }
    // Counted after pushing: the stream also counts the callbacks it waits
    // through for the first frames.
    _exhaustCount = stream.exhaustCount;
    _queue.removeWhere((queued) => queued.end <= _written);
  }

  /// The frames from [start] (output clock): the blocks queued, a gain per
  /// track (moved to its target over the chunk), the pans, the master gain,
  /// the limiter.
  Float32List _mix(int start, int frames) {
    var out = Float32List(frames * 2);
    var end = start + frames;
    var trackCount = _tracks.length;
    for (var queued in _queue) {
      trackCount = math.max(trackCount, queued.block.trackCount);
    }
    var reverb = _reverb;
    Float32List? sends;
    var fed = false;
    var chorus = _chorus;
    var chorusFed = false;
    for (var track = 0; track < trackCount; track++) {
      var mix = _track(track);
      var from = mix.gain;
      var to = mix.target;
      mix.gain = to;
      var sendFrom = mix.reverb * from;
      var sendTo = mix.reverbTarget * to;
      mix.reverb = mix.reverbTarget;
      var chorusFrom = mix.chorus * from;
      var chorusTo = mix.chorusTarget * to;
      mix.chorus = mix.chorusTarget;
      if (from == 0 && to == 0) {
        continue;
      }
      var pan = midiStereoPan(mix.pan);
      Float32List? input;
      if (reverb != null && (sendFrom > 0 || sendTo > 0)) {
        if (!fed) {
          fed = true;
          sends = reverb.input(frames);
        }
        input = sends;
      }
      Float32List? chorusLeft;
      Float32List? chorusRight;
      if (chorus != null && (chorusFrom > 0 || chorusTo > 0)) {
        if (!chorusFed) {
          chorusFed = true;
          chorus.input(frames);
        }
        chorusLeft = chorus.inputLeft;
        chorusRight = chorus.inputRight;
      }
      for (var queued in _queue) {
        var block = queued.block;
        if (track >= block.trackCount ||
            queued.end <= start ||
            queued.start >= end) {
          continue;
        }
        var left = block.left[track];
        var right = block.right[track];
        var first = math.max(start, queued.start);
        var last = math.min(end, queued.end);
        for (var frame = first; frame < last; frame++) {
          var i = frame - start;
          var gain = (from + (to - from) * i / frames) * midiMasterGain;
          var l = left[frame - queued.start] * gain;
          var r = right[frame - queued.start] * gain;
          out[2 * i] += l * pan.leftToLeft + r * pan.rightToLeft;
          out[2 * i + 1] += l * pan.leftToRight + r * pan.rightToRight;
          if (input != null) {
            input[i] +=
                (left[frame - queued.start] + right[frame - queued.start]) *
                (sendFrom + (sendTo - sendFrom) * i / frames) *
                midiMasterGain;
          }
          if (chorusLeft != null && chorusRight != null) {
            // The track panned, times its send.
            var send =
                (chorusFrom + (chorusTo - chorusFrom) * i / frames) *
                midiMasterGain;
            var a = left[frame - queued.start] * send;
            var b = right[frame - queued.start] * send;
            chorusLeft[i] += a * pan.leftToLeft + b * pan.rightToLeft;
            chorusRight[i] += a * pan.leftToRight + b * pan.rightToRight;
          }
        }
      }
    }
    if (reverb != null && reverb.process(frames, fed: fed)) {
      var level = reverb.level;
      var wetLeft = reverb.left;
      var wetRight = reverb.right;
      for (var i = 0; i < frames; i++) {
        out[2 * i] += wetLeft[i] * level;
        out[2 * i + 1] += wetRight[i] * level;
      }
    }
    if (chorus != null && chorus.process(frames, fed: chorusFed)) {
      var level = chorus.level;
      var wetLeft = chorus.left;
      var wetRight = chorus.right;
      for (var i = 0; i < frames; i++) {
        out[2 * i] += wetLeft[i] * level;
        out[2 * i + 1] += wetRight[i] * level;
      }
    }
    _limiter.process(out);
    return out;
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _stopwatch.stop();
    stream.close();
  }
}
