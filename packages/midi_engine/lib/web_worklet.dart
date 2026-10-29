/// The AudioWorklet player: the engine runs in an AudioWorklet, on the audio
/// thread, and this is its page side. The worklet module is built from Dart
/// by `dart run milomedy_midi_engine:setup_web_worklet`, next to the page.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'midi_engine.dart';
import 'src/worklet_js.dart';

export 'src/worklet_js.dart'
    show midiWorkletDefaultUrl, midiWorkletProcessorName;

/// The last position reported by the worklet.
class _Report {
  final double position;
  final double time;
  final double speed;

  _Report(this.position, this.time, this.speed);
}

/// A player whose engine runs in an AudioWorklet: nothing is rendered ahead,
/// so a command is heard after the output latency only, and a busy page
/// never makes a gap.
class MidiWorkletPlayer implements MidiTransport {
  /// The audio context.
  final web.BaseAudioContext context;

  /// The worklet node.
  final web.AudioWorkletNode node;

  /// The mix of the tracks.
  final MidiMixer mixer;

  final bool _ownsContext;
  var _state = MidiPlayerState.stopped;
  final _stateController = StreamController<MidiPlayerState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  MidiTimeline? _timeline;
  var _position = 0.0;
  _Report? _report;
  var _speed = 1.0;
  var _transpose = 0;
  (double, double)? _loop;
  var _syncId = 0;
  final _syncs = <int, Completer<void>>{};

  MidiWorkletPlayer._(
    this.context,
    this.node,
    int trackCount,
    this._ownsContext,
  ) : mixer = MidiMixer(trackCount) {
    node.port.onmessage = (web.MessageEvent event) {
      var data = event.data.dartify();
      if (data is Map) {
        _onEvent(data);
      }
    }.toJS;
  }

  /// A player of one track per synth of [synths], on [context] (a new
  /// AudioContext by default), its worklet module at [url], connected to
  /// [destination] (the context's by default).
  static Future<MidiWorkletPlayer> create({
    required List<MidiSynthSpec> synths,
    web.BaseAudioContext? context,
    String url = midiWorkletDefaultUrl,
    web.AudioNode? destination,
  }) async {
    var ownsContext = context == null;
    context ??= web.AudioContext();
    await context.audioWorklet.addModule(url).toDart;
    var processorOptions = JSObject()
      ..['synths'] = [for (var spec in synths) spec.toMap()].jsify();
    var node = web.AudioWorkletNode(
      context,
      midiWorkletProcessorName,
      web.AudioWorkletNodeOptions(
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2.toJS].toJS,
        processorOptions: processorOptions,
      ),
    );
    node.connect(destination ?? context.destination);
    return MidiWorkletPlayer._(context, node, synths.length, ownsContext);
  }

  void _send(Map<String, Object?> command) =>
      node.port.postMessage(command.jsify());

  void _onEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      case MidiHostEvents.state:
        var state = MidiPlayerState.values.byName(event['state'] as String);
        _position = (event['position'] as num).toDouble();
        if (state != MidiPlayerState.playing) {
          _report = null;
        }
        _setState(state);
      case MidiHostEvents.position:
        _report = _Report(
          (event['position'] as num).toDouble(),
          (event['time'] as num).toDouble(),
          (event['speed'] as num).toDouble(),
        );
      case MidiHostEvents.sync:
        _syncs.remove((event['id'] as num).toInt())?.complete();
      case MidiHostEvents.error:
        _errorController.add(event['message'] as String);
    }
  }

  void _setState(MidiPlayerState state) {
    if (state != _state) {
      _state = state;
      _stateController.add(state);
    }
  }

  /// The errors reported by the worklet.
  Stream<String> get onError => _errorController.stream;

  /// Completes once the worklet has handled the commands sent before.
  Future<void> sync() {
    var id = ++_syncId;
    var completer = _syncs[id] = Completer<void>();
    _send({'type': MidiHostCommands.sync, 'id': id});
    return completer.future;
  }

  @override
  MidiPlayerState get state => _state;

  @override
  Stream<MidiPlayerState> get onState => _stateController.stream;

  @override
  bool get isPlaying => _state == MidiPlayerState.playing;

  @override
  MidiTimeline? get timeline => _timeline;

  @override
  void load(MidiTimeline timeline) {
    _timeline = timeline;
    _position = timeline.start;
    _report = null;
    _setState(MidiPlayerState.stopped);
    _send({
      'type': MidiHostCommands.load,
      'timeline': midiTimelineToMap(timeline),
    });
  }

  @override
  void replace(MidiTimeline timeline) {
    if (_timeline == null) {
      load(timeline);
      return;
    }
    _timeline = timeline;
    _send({
      'type': MidiHostCommands.replace,
      'timeline': midiTimelineToMap(timeline),
      'at': position,
    });
  }

  /// The delay between a frame rendered and heard, in seconds.
  double get _latency {
    var context = this.context;
    if (context.isA<web.AudioContext>()) {
      var audioContext = context as web.AudioContext;
      return audioContext.baseLatency + audioContext.outputLatency;
    }
    return 0;
  }

  @override
  double get position {
    var report = _report;
    if (_state != MidiPlayerState.playing || report == null) {
      return _position;
    }
    var heard = context.currentTime - _latency;
    var position = report.position + (heard - report.time) * report.speed;
    var loop = _loop;
    if (loop != null && report.position < loop.$2 && position >= loop.$2) {
      position = loop.$1 + (position - loop.$2) % (loop.$2 - loop.$1);
    }
    return position;
  }

  void _sendMix() {
    _send({
      'type': MidiHostCommands.mix,
      'tracks': [
        for (var track = 0; track < mixer.tracks.length; track++)
          [mixer.gainOf(track), mixer.panOf(track)],
      ],
    });
  }

  @override
  void setVolume(int track, double volume) {
    mixer.tracks[track].volume = volume;
    _sendMix();
  }

  @override
  void setPan(int track, double pan) {
    mixer.tracks[track].pan = pan;
    _sendMix();
  }

  @override
  void setMute(int track, bool mute) {
    mixer.tracks[track].mute = mute;
    _sendMix();
  }

  @override
  void setSolo(int track, bool solo) {
    mixer.tracks[track].solo = solo;
    _sendMix();
  }

  @override
  double get speed => _speed;

  @override
  set speed(double speed) {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }
    _speed = speed;
    _send({'type': MidiHostCommands.speed, 'value': speed});
  }

  @override
  int get transpose => _transpose;

  @override
  set transpose(int transpose) {
    _transpose = transpose;
    _send({'type': MidiHostCommands.transpose, 'value': transpose});
  }

  @override
  void setLoop(double? start, double? end) {
    _loop = start == null || end == null || end <= start ? null : (start, end);
    _send({'type': MidiHostCommands.loop, 'start': start, 'end': end});
  }

  /// Sets the synth of [track] (an instrument, a register): heard at once.
  void setSynth(int track, MidiSynthSpec spec) {
    _send({
      'type': MidiHostCommands.synth,
      'track': track,
      'spec': spec.toMap(),
    });
  }

  @override
  Future<void> play() async {
    if (_timeline == null || _state == MidiPlayerState.playing) {
      return;
    }
    var context = this.context;
    if (context.isA<web.AudioContext>() && context.state != 'running') {
      await (context as web.AudioContext).resume().toDart;
    }
    _send({'type': MidiHostCommands.play});
    _setState(MidiPlayerState.playing);
  }

  @override
  void pause() {
    if (_state != MidiPlayerState.playing) {
      return;
    }
    _position = position;
    _report = null;
    _setState(MidiPlayerState.paused);
    _send({'type': MidiHostCommands.pause});
  }

  @override
  void stop() {
    _position = _timeline?.start ?? 0;
    _report = null;
    _setState(MidiPlayerState.stopped);
    _send({'type': MidiHostCommands.stop});
  }

  @override
  void seek(double position) {
    _position = position;
    _report = null;
    if (_state == MidiPlayerState.stopped) {
      _setState(MidiPlayerState.paused);
    }
    _send({'type': MidiHostCommands.seek, 'position': position});
  }

  @override
  Future<void> close() async {
    node.port.onmessage = null;
    node.port.close();
    node.disconnect();
    if (_ownsContext && context.isA<web.AudioContext>()) {
      await (context as web.AudioContext).close().toDart;
    }
    for (var completer in _syncs.values) {
      completer.completeError(StateError('closed'));
    }
    _syncs.clear();
    await _stateController.close();
    await _errorController.close();
  }
}
