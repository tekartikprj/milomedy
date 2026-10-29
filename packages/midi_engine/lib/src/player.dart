/// The player (from accordelio's): keeps an audio output fed with blocks
/// rendered by the engine, a little ahead of its clock, and tells where the
/// music is.
library;

import 'dart:async';
import 'dart:math' as math;

import 'engine.dart';
import 'mixer.dart';
import 'sink.dart';
import 'timeline.dart';

/// The states of the player.
enum MidiPlayerState {
  /// At the start (or after the end).
  stopped,

  /// Playing.
  playing,

  /// Paused somewhere.
  paused,
}

/// A block scheduled: when on the output clock, from which song time.
class _Scheduled {
  final double when;
  final double songStart;
  final double seconds;
  final double speed;

  _Scheduled(this.when, this.songStart, this.seconds, this.speed);
}

/// The player.
class MidiPlayer {
  /// The output.
  final MidiAudioSink sink;

  /// The engine.
  final MidiEngine engine;

  /// The mix of the tracks.
  final MidiMixer mixer;

  /// The frames of a block.
  static const blockFrames = 2048;

  /// How far ahead of the output clock the music is rendered (seconds):
  /// longer when the page is hidden (its timers slowed down).
  var lookahead = 0.25;

  final _scheduled = <_Scheduled>[];
  var _scheduledUntil = 0.0;
  Timer? _timer;
  var _state = MidiPlayerState.stopped;
  final _stateController = StreamController<MidiPlayerState>.broadcast();

  /// A player of [engine] on [sink], its tracks mixed by [mixer] (each at
  /// full volume in the middle by default).
  MidiPlayer(this.sink, this.engine, {MidiMixer? mixer})
    : mixer = mixer ?? MidiMixer(engine.synths.length) {
    if (sink.sampleRate != engine.sampleRate) {
      throw ArgumentError.value(
        engine.sampleRate,
        'engine',
        'sample rate is not the output\'s ${sink.sampleRate}',
      );
    }
    applyMix();
  }

  /// The state.
  MidiPlayerState get state => _state;

  /// The state and its changes.
  Stream<MidiPlayerState> get onState => _stateController.stream;

  /// True while playing.
  bool get isPlaying => _state == MidiPlayerState.playing;

  /// The timeline played, null before [load].
  MidiTimeline? get timeline => engine.timeline;

  void _setState(MidiPlayerState state) {
    if (state != _state) {
      _state = state;
      _stateController.add(state);
    }
  }

  /// Loads [timeline], stopped at its start.
  void load(MidiTimeline timeline) {
    _halt();
    engine.load(timeline);
    _setState(MidiPlayerState.stopped);
  }

  /// Plays [timeline] instead of the current one from the same place (an
  /// edit): heard at once.
  void replace(MidiTimeline timeline) {
    if (engine.timeline == null) {
      load(timeline);
      return;
    }
    var position = this.position;
    _cancelScheduled();
    engine.replace(timeline, at: position);
    _restartPump();
  }

  /// The song time heard now, in seconds (negative in a count-in).
  double get position {
    if (_state != MidiPlayerState.playing || _scheduled.isEmpty) {
      return engine.position;
    }
    var now = sink.currentTime;
    _Scheduled? current;
    for (var block in _scheduled) {
      if (block.when <= now) {
        current = block;
      } else {
        break;
      }
    }
    if (current == null) {
      return _scheduled.first.songStart;
    }
    var into = math.min(now - current.when, current.seconds);
    return current.songStart + into * current.speed;
  }

  /// Sends the mix of every track to the output (after changing [mixer]
  /// directly).
  void applyMix() {
    for (var track = 0; track < mixer.tracks.length; track++) {
      sink.setTrackMix(
        track,
        gain: mixer.gainOf(track),
        pan: mixer.panOf(track),
      );
    }
  }

  /// Sets the volume of [track], 0 to 1.
  void setVolume(int track, double volume) {
    mixer.tracks[track].volume = volume;
    applyMix();
  }

  /// Sets the pan of [track], -1 to 1.
  void setPan(int track, double pan) {
    mixer.tracks[track].pan = pan;
    applyMix();
  }

  /// Mutes [track] or not.
  void setMute(int track, bool mute) {
    mixer.tracks[track].mute = mute;
    applyMix();
  }

  /// Solos [track] or not.
  void setSolo(int track, bool solo) {
    mixer.tracks[track].solo = solo;
    applyMix();
  }

  /// The song seconds played in a second.
  double get speed => engine.speed;

  /// Sets the speed: heard at once, from the same place.
  set speed(double speed) {
    engine.speed = speed;
    resync();
  }

  /// The transposition, in semitones.
  int get transpose => engine.transpose;

  /// Sets the transposition: heard at once.
  set transpose(int transpose) {
    engine.transpose = transpose;
    resync();
  }

  /// Loops from [start] to [end] (song seconds), null for no loop.
  void setLoop(double? start, double? end) {
    engine.setLoop(start, end);
    resync();
  }

  /// Plays from where it is (from the start after the end).
  Future<void> play() async {
    var timeline = engine.timeline;
    if (timeline == null || _state == MidiPlayerState.playing) {
      return;
    }
    await sink.resume();
    if (engine.ended || engine.position >= timeline.end) {
      engine.seek(timeline.start);
    }
    _setState(MidiPlayerState.playing);
    _restartPump();
  }

  /// Pauses where it is.
  void pause() {
    if (_state != MidiPlayerState.playing) {
      return;
    }
    var position = this.position;
    _halt();
    engine.seek(position);
    engine.releaseAll();
    _setState(MidiPlayerState.paused);
  }

  /// Stops and goes back to the start.
  void stop() {
    _halt();
    var timeline = engine.timeline;
    if (timeline != null) {
      engine.seek(timeline.start);
    }
    _setState(MidiPlayerState.stopped);
  }

  /// Goes to [position] (song seconds).
  void seek(double position) {
    _cancelScheduled();
    engine.seek(position);
    if (_state == MidiPlayerState.playing) {
      _restartPump();
    } else if (_state == MidiPlayerState.stopped) {
      _setState(MidiPlayerState.paused);
    }
  }

  void _halt() {
    _timer?.cancel();
    _timer = null;
    _cancelScheduled();
  }

  void _cancelScheduled() {
    sink.cancel();
    _scheduled.clear();
  }

  /// Renders again from the place heard now: a change of the engine or of
  /// a synth (an instrument, a register) heard at once.
  void resync() {
    if (_state != MidiPlayerState.playing) {
      return;
    }
    var position = this.position;
    _cancelScheduled();
    engine.seek(position);
    _restartPump();
  }

  void _restartPump() {
    if (_state != MidiPlayerState.playing) {
      return;
    }
    _scheduledUntil = sink.currentTime + sink.startLatency;
    _pump();
    _timer ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _pump());
  }

  /// Renders until [lookahead] ahead of the output clock.
  void pump() => _pump();

  void _pump() {
    if (_state != MidiPlayerState.playing) {
      return;
    }
    var now = sink.currentTime;
    if (_scheduledUntil < now && !engine.ended) {
      // Late (a busy page): start again a little ahead.
      _scheduledUntil = now + sink.startLatency;
    }
    while (_scheduledUntil < now + lookahead && !engine.ended) {
      var frames = blockFrames;
      // A block never crosses the loop end: its song time stays linear.
      var toLoop = engine.framesToLoopEnd;
      if (toLoop != null && toLoop > 0 && toLoop < frames) {
        frames = toLoop;
      }
      var block = engine.render(frames);
      sink.schedule(_scheduledUntil, block);
      var seconds = frames / sink.sampleRate;
      _scheduled.add(
        _Scheduled(_scheduledUntil, block.songStart, seconds, block.speed),
      );
      _scheduledUntil += seconds;
    }
    _scheduled.removeWhere((block) => block.when + block.seconds < now - 1);
    if (engine.ended && now >= _scheduledUntil) {
      _halt();
      _setState(MidiPlayerState.stopped);
    }
  }

  /// Stops and closes the output.
  Future<void> close() async {
    _halt();
    await _stateController.close();
    await sink.close();
  }
}
