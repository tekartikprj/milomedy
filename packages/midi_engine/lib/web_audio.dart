/// The Web Audio output (from accordelio's): each block of each track in a
/// stereo AudioBuffer started at its time on the AudioContext clock,
/// through the gain and the pan of its track (heard at once), then a
/// limiter and the master gain.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'midi_engine.dart';

class _TrackNodes {
  final web.GainNode gain;
  final web.StereoPannerNode panner;

  _TrackNodes(this.gain, this.panner);
}

/// The Web Audio output.
class MidiWebAudioSink implements MidiAudioSink {
  final web.AudioContext _context;
  late final web.DynamicsCompressorNode _limiter;
  final _tracks = <_TrackNodes>[];
  final _sources = <web.AudioBufferSourceNode>[];

  /// An output on a new AudioContext (suspended until [resume], which must
  /// follow a user gesture).
  MidiWebAudioSink() : _context = web.AudioContext() {
    _limiter = _context.createDynamicsCompressor()
      ..threshold.value = -3
      ..knee.value = 0
      ..ratio.value = 20
      ..attack.value = 0.002
      ..release.value = 0.1;
    var master = _context.createGain()..gain.value = midiMasterGain;
    _limiter.connect(master);
    master.connect(_context.destination);
  }

  _TrackNodes _track(int track) {
    while (_tracks.length <= track) {
      var gain = _context.createGain();
      var panner = _context.createStereoPanner();
      gain.connect(panner);
      panner.connect(_limiter);
      _tracks.add(_TrackNodes(gain, panner));
    }
    return _tracks[track];
  }

  @override
  int get sampleRate => _context.sampleRate.round();

  @override
  double get currentTime => _context.currentTime;

  @override
  double get startLatency => 0.04;

  @override
  Future<void> resume() async {
    if (_context.state != 'running') {
      await _context.resume().toDart;
    }
  }

  @override
  void schedule(double when, MidiRenderBlock block) {
    for (var track = 0; track < block.trackCount; track++) {
      var left = block.left[track];
      var right = block.right[track];
      if (!_hasSound(left) && !_hasSound(right)) {
        continue;
      }
      var buffer = _context.createBuffer(2, block.frames, _context.sampleRate);
      buffer.copyToChannel(left.toJS, 0);
      buffer.copyToChannel(right.toJS, 1);
      var source = _context.createBufferSource()..buffer = buffer;
      source.connect(_track(track).gain);
      source.start(when);
      _sources.add(source);
      source.onended = ((web.Event _) {
        _sources.remove(source);
      }).toJS;
    }
  }

  static bool _hasSound(List<double> samples) {
    for (var i = 0; i < samples.length; i += 8) {
      if (samples[i] != 0) {
        return true;
      }
    }
    return samples.isNotEmpty && samples.last != 0;
  }

  @override
  void cancel() {
    for (var source in _sources) {
      try {
        source.stop();
      } catch (_) {
        // Not started yet or already stopped.
      }
      source.disconnect();
    }
    _sources.clear();
  }

  @override
  void setTrackMix(int track, {required double gain, required double pan}) {
    var nodes = _track(track);
    var now = _context.currentTime;
    nodes.gain.gain.setTargetAtTime(gain, now, 0.02);
    nodes.panner.pan.setTargetAtTime(pan, now, 0.02);
  }

  @override
  Future<void> close() async {
    cancel();
    await _context.close().toDart;
  }
}
