/// The player side of an engine host, wherever the host runs (an
/// AudioWorklet, an isolate): it sends the commands of `protocol.dart`,
/// follows the state and position events, and tells the position heard.
library;

import 'dart:async';
import 'dart:typed_data';

import 'meters.dart';
import 'mixer.dart';
import 'protocol.dart';
import 'speed_trainer.dart';
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
  var _tuneCents = 0.0;
  MidiSpeedTrainer? _trainer;
  (double, double)? _loop;

  /// The sequence number of the last command that set the speed: the speed
  /// reported before is stale.
  var _speedSeq = 0;
  final _speedController = StreamController<double>.broadcast();
  late MidiTrackMeters _meters;
  final _metersController = StreamController<MidiTrackMeters>.broadcast();
  var _syncId = 0;
  final _syncs = <int, Completer<void>>{};

  /// The sequence number of the last command sent.
  var _seq = 0;

  /// The sequence number of the last command that changes the state: the
  /// state and position events sent before the host handled it are stale.
  var _stateSeq = 0;

  /// A player of [trackCount] tracks.
  MidiHostPlayer({required int trackCount}) : mixer = MidiMixer(trackCount) {
    _meters = MidiTrackMeters.silent(trackCount);
  }

  /// Sends [command] to the host (for implementations).
  void sendCommand(Map<String, Object?> command);

  /// Sends [command] to the host, moving the buffers of [transfer] instead of
  /// copying them when the host runs elsewhere (the AudioWorklet): they are
  /// unusable here once sent. As [sendCommand] by default (for
  /// implementations).
  void sendCommandTransfer(
    Map<String, Object?> command,
    List<ByteBuffer> transfer,
  ) => sendCommand(command);

  /// The time of the clock of the position reports at which the output is
  /// heard now, in seconds (for implementations). A report without a time is
  /// the position heard when it is received.
  double get clock;

  /// Makes the output ready before playing (for implementations).
  Future<void> resumeOutput() async {}

  /// Sends [command], numbered; [changesState] for the commands after which
  /// the state and position events sent before are stale; the buffers of
  /// [transfer] moved (see [sendCommandTransfer]).
  void _send(
    Map<String, Object?> command, {
    bool changesState = false,
    bool setsSpeed = false,
    List<ByteBuffer>? transfer,
  }) {
    _seq++;
    if (changesState) {
      _stateSeq = _seq;
    }
    if (setsSpeed) {
      _speedSeq = _seq;
    }
    var numbered = {...command, 'seq': _seq};
    if (transfer == null) {
      sendCommand(numbered);
    } else {
      sendCommandTransfer(numbered, transfer);
    }
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
          _silenceMeters();
        }
        _setState(state);
      case MidiHostEvents.position:
        var time = event['time'] as num?;
        var speed = (event['speed'] as num).toDouble();
        _report = _Report(
          (event['position'] as num).toDouble(),
          time?.toDouble() ?? clock,
          speed,
        );
        // The speed of the host (a trainer changes it), unless a newer
        // command set it.
        if ((seq == null || seq >= _speedSeq) && speed != _speed) {
          _speed = speed;
          _speedController.add(speed);
        }
        // Not after a pause or the end (the isolate host sends its reports
        // once heard, after the state).
        var meters = _state == MidiPlayerState.playing
            ? MidiTrackMeters.fromEvent(event, mixer.tracks.length)
            : null;
        if (meters != null) {
          _meters = meters;
          _metersController.add(meters);
        }
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

  /// The speed changes made by the host: the steps of the speed trainer.
  Stream<double> get onSpeed => _speedController.stream;

  /// The meters of the tracks, as last reported by the host (about 30 times
  /// a second while playing, silent otherwise).
  MidiTrackMeters get meters => _meters;

  /// The meters as they are reported, and when they go silent (a pause, a
  /// stop).
  Stream<MidiTrackMeters> get onMeters => _metersController.stream;

  /// The peak level of each track since the previous report, after its
  /// volume: 1 is full scale.
  List<double> get trackLevels => _meters.levels;

  /// The keys sounding on each track (the notes started and not released,
  /// transposed), for a keyboard view.
  List<Set<int>> get soundingKeys => _meters.keys;

  void _silenceMeters() {
    if (!_meters.isSilent) {
      _meters = MidiTrackMeters.silent(mixer.tracks.length);
      _metersController.add(_meters);
    }
  }

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
    _silenceMeters();
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
          [mixer.gainOf(track), mixer.panOf(track), mixer.reverbOf(track)],
      ],
      'reverb': mixer.reverbLevel,
    });
  }

  @override
  void setReverb(int track, double send) {
    mixer.tracks[track].reverb = send;
    _sendMix();
  }

  @override
  double get reverbLevel => mixer.reverbLevel;

  @override
  set reverbLevel(double level) {
    mixer.reverbLevel = level;
    _sendMix();
  }

  @override
  double get tuneCents => _tuneCents;

  @override
  set tuneCents(double cents) {
    if (!cents.isFinite || cents < -100 || cents > 100) {
      throw ArgumentError.value(cents, 'tuneCents', 'must be -100 to 100');
    }
    _tuneCents = cents;
    _send({'type': MidiHostCommands.tune, 'value': cents});
  }

  @override
  MidiSpeedTrainer? get speedTrainer => _trainer;

  @override
  void setSpeedTrainer({
    required double from,
    required double to,
    required double step,
    int everyPasses = 1,
  }) {
    var trainer = _trainer = MidiSpeedTrainer(
      from: from,
      to: to,
      step: step,
      everyPasses: everyPasses,
    );
    _speed = from;
    _send({
      'type': MidiHostCommands.speedTrainer,
      'trainer': trainer.toMap(),
    }, setsSpeed: true);
  }

  @override
  void clearSpeedTrainer() {
    _trainer = null;
    _send({'type': MidiHostCommands.speedTrainer, 'trainer': null});
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
    _trainer = null;
    _send({'type': MidiHostCommands.speed, 'value': speed}, setsSpeed: true);
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

  /// Loads the SoundFont [bytes] (an `.sf2` file) as [id]: the tracks whose
  /// spec plays it get their synth. Completes once the host has read it; an
  /// error (no SoundFont support registered in the host, a bad file) comes
  /// on [onError].
  ///
  /// With [transfer], the bytes are moved to the host when it runs elsewhere
  /// (the AudioWorklet on the web) instead of copied: a large SoundFont is in
  /// memory once, not twice (32 MB for GeneralUser GS, the page and the
  /// worklet in the same process on iOS). [bytes] are then empty here; a view
  /// on part of a larger buffer is copied first.
  Future<void> loadSoundFont(
    String id,
    Uint8List bytes, {
    bool transfer = false,
  }) {
    if (transfer &&
        (bytes.offsetInBytes != 0 ||
            bytes.lengthInBytes != bytes.buffer.lengthInBytes)) {
      bytes = Uint8List.fromList(bytes);
    }
    _send({
      'type': MidiHostCommands.soundFont,
      'id': id,
      'bytes': bytes,
    }, transfer: transfer ? [bytes.buffer] : null);
    return sync();
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
    _silenceMeters();
    _setState(MidiPlayerState.paused);
    _send({'type': MidiHostCommands.pause}, changesState: true);
  }

  @override
  void stop() {
    _position = _timeline?.start ?? 0;
    _report = null;
    _silenceMeters();
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
    await _speedController.close();
    await _metersController.close();
  }
}
