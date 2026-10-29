/// The player side of an engine host, wherever the host runs (an
/// AudioWorklet, an isolate): it sends the commands of `protocol.dart`,
/// follows the state and position events, and tells the position heard.
library;

import 'dart:async';

import 'mixer.dart';
import 'protocol.dart';
import 'synth_spec.dart';
import 'timeline.dart';
import 'transport.dart';

/// The last position reported by the host.
class _Report {
  final double position;
  final double time;
  final double speed;

  _Report(this.position, this.time, this.speed);
}

/// A player driving an engine host through messages. An implementation
/// sends the commands ([sendCommand]), gives the clock of the reports
/// ([clock]), passes the events to [handleEvent] and makes its output ready
/// in [resumeOutput].
abstract class MidiHostPlayer implements MidiTransport {
  /// The mix of the tracks.
  final MidiMixer mixer;

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

  /// The sequence number of the last command sent.
  var _seq = 0;

  /// The sequence number of the last command that changes the state: the
  /// state and position events sent before the host handled it are stale.
  var _stateSeq = 0;

  /// A player of [trackCount] tracks.
  MidiHostPlayer({required int trackCount}) : mixer = MidiMixer(trackCount);

  /// Sends [command] to the host (for implementations).
  void sendCommand(Map<String, Object?> command);

  /// The time of the clock of the position reports at which the output is
  /// heard now, in seconds (for implementations). A report without a time is
  /// the position heard when it is received.
  double get clock;

  /// Makes the output ready before playing (for implementations).
  Future<void> resumeOutput() async {}

  /// Sends [command], numbered; [changesState] for the commands after which
  /// the state and position events sent before are stale.
  void _send(Map<String, Object?> command, {bool changesState = false}) {
    _seq++;
    if (changesState) {
      _stateSeq = _seq;
    }
    sendCommand({...command, 'seq': _seq});
  }

  /// Handles an event of the host (for implementations).
  void handleEvent(Map<Object?, Object?> event) {
    var type = event['type'];
    var seq = (event['seq'] as num?)?.toInt();
    if (seq != null &&
        seq < _stateSeq &&
        (type == MidiHostEvents.state || type == MidiHostEvents.position)) {
      return;
    }
    switch (type) {
      case MidiHostEvents.state:
        var state = MidiPlayerState.values.byName(event['state'] as String);
        _position = (event['position'] as num).toDouble();
        if (state != MidiPlayerState.playing) {
          _report = null;
        }
        _setState(state);
      case MidiHostEvents.position:
        var time = event['time'] as num?;
        _report = _Report(
          (event['position'] as num).toDouble(),
          time?.toDouble() ?? clock,
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

  /// The errors reported by the host.
  Stream<String> get onError => _errorController.stream;

  /// Completes once the host has handled the commands sent before.
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
    }, changesState: true);
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

  @override
  double get position {
    var report = _report;
    if (_state != MidiPlayerState.playing || report == null) {
      return _position;
    }
    var position = report.position + (clock - report.time) * report.speed;
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
    await resumeOutput();
    _send({'type': MidiHostCommands.play}, changesState: true);
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
    _send({'type': MidiHostCommands.pause}, changesState: true);
  }

  @override
  void stop() {
    _position = _timeline?.start ?? 0;
    _report = null;
    _setState(MidiPlayerState.stopped);
    _send({'type': MidiHostCommands.stop}, changesState: true);
  }

  @override
  void seek(double position) {
    _position = position;
    _report = null;
    if (_state == MidiPlayerState.stopped) {
      _setState(MidiPlayerState.paused);
    }
    _send({
      'type': MidiHostCommands.seek,
      'position': position,
    }, changesState: true);
  }

  /// Fails the pending syncs and closes the streams: implementations close
  /// their host, then call it.
  @override
  Future<void> close() async {
    for (var completer in _syncs.values) {
      completer.completeError(StateError('closed'));
    }
    _syncs.clear();
    await _stateController.close();
    await _errorController.close();
  }
}
