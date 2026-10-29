/// The engine host: runs an engine where the audio is made (an AudioWorklet,
/// later an isolate), driven by the messages of `protocol.dart`. It renders
/// the frames the output asks for, mixed, and reports its state and its
/// position. Nothing is rendered ahead: a command is heard from the next
/// block.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';

import 'engine.dart';
import 'mixer.dart';
import 'protocol.dart';
import 'synth_spec.dart';
import 'transport.dart';

/// The host.
class MidiEngineHost {
  /// The sample rate.
  final int sampleRate;

  /// The engine.
  final MidiEngine engine;

  /// Sends an event to the player.
  final void Function(Map<String, Object?> event) send;

  /// The frames between two position reports.
  final int reportFrames;

  final MidiStereoMixdown _mixdown;
  var _state = MidiPlayerState.stopped;
  var _untilReport = 0;

  /// The sequence number of the last command handled, sent back with the
  /// state and position events so that the player can tell the stale ones.
  int? _seq;

  /// The frames of the fade out before a pause or a stop.
  final int _fadeFrames;

  /// The frames of the fade still to play, 0 when not fading.
  var _fadeLeft = 0;

  /// What to do once faded out.
  void Function()? _afterFade;

  /// A host of the synths of [synths] at [sampleRate].
  MidiEngineHost({
    required this.sampleRate,
    required List<MidiSynthSpec> synths,
    required this.send,
    this.reportFrames = 4096,
  }) : engine = MidiEngine(
         sampleRate: sampleRate,
         synths: [for (var spec in synths) spec.build(sampleRate)],
       ),
       _mixdown = MidiStereoMixdown(sampleRate: sampleRate),
       _fadeFrames = (0.005 * sampleRate).round();

  /// The state.
  MidiPlayerState get state => _state;

  void _setState(MidiPlayerState state) {
    _state = state;
    _untilReport = 0;
    send({
      'type': MidiHostEvents.state,
      'state': state.name,
      'position': engine.position,
      'seq': ?_seq,
    });
  }

  /// Handles a command; a failure is sent as an error event.
  void handle(Map<Object?, Object?> command) {
    _seq = (command['seq'] as num?)?.toInt() ?? _seq;
    try {
      _handle(command);
    } catch (e) {
      send({'type': MidiHostEvents.error, 'message': '$e'});
    }
  }

  void _handle(Map<Object?, Object?> command) {
    double number(String key) => (command[key] as num).toDouble();
    switch (command['type']) {
      case MidiHostCommands.load:
        _cancelFade();
        engine.load(midiTimelineFromMap(command['timeline'] as Map));
        _setState(MidiPlayerState.stopped);
      case MidiHostCommands.replace:
        var at = command['at'] as num?;
        engine.replace(
          midiTimelineFromMap(command['timeline'] as Map),
          at: at?.toDouble(),
        );
        _untilReport = 0;
      case MidiHostCommands.play:
        var timeline = engine.timeline;
        if (timeline == null) {
          return;
        }
        if (_fadeLeft > 0) {
          // Playing again while fading out: go on.
          _cancelFade();
          return;
        }
        if (_state == MidiPlayerState.playing) {
          return;
        }
        if (engine.ended || engine.position >= timeline.end) {
          engine.silence();
          engine.seek(timeline.start);
        }
        _setState(MidiPlayerState.playing);
      case MidiHostCommands.pause:
        if (_state == MidiPlayerState.playing) {
          var at = engine.position;
          _fadeOut(() {
            engine.silence();
            engine.seek(at);
            _setState(MidiPlayerState.paused);
          });
        }
      case MidiHostCommands.stop:
        void stop() {
          engine.silence();
          var timeline = engine.timeline;
          if (timeline != null) {
            engine.seek(timeline.start);
          }
          _setState(MidiPlayerState.stopped);
        }
        if (_state == MidiPlayerState.playing) {
          _fadeOut(stop);
        } else {
          stop();
        }
      case MidiHostCommands.seek:
        var position = number('position');
        if (_state == MidiPlayerState.playing) {
          engine.seek(position);
          _untilReport = 0;
        } else {
          engine.silence();
          engine.seek(position);
          _setState(MidiPlayerState.paused);
        }
      case MidiHostCommands.loop:
        var start = command['start'] as num?;
        var end = command['end'] as num?;
        engine.setLoop(start?.toDouble(), end?.toDouble());
      case MidiHostCommands.speed:
        engine.speed = number('value');
        _untilReport = 0;
      case MidiHostCommands.transpose:
        engine.transpose = (command['value'] as num).toInt();
        _resync();
      case MidiHostCommands.mix:
        var tracks = command['tracks'] as List;
        for (var (track, mix) in tracks.indexed) {
          var values = (mix as List).cast<num>();
          _mixdown.setTrack(
            track,
            gain: values[0].toDouble(),
            pan: values[1].toDouble(),
          );
        }
      case MidiHostCommands.synth:
        var track = (command['track'] as num).toInt();
        var synth = engine.synths[track];
        if (synth is DartSynth) {
          MidiSynthSpec.fromMap(command['spec'] as Map).applyTo(synth);
          _resync();
        }
      case MidiHostCommands.sync:
        send({'type': MidiHostEvents.sync, 'id': command['id']});
      default:
        throw ArgumentError.value(command['type'], 'type', 'unknown command');
    }
  }

  /// Plays again from the same place: a change heard at once.
  void _resync() {
    if (_state == MidiPlayerState.playing && _fadeLeft == 0) {
      engine.seek(engine.position);
    }
  }

  void _fadeOut(void Function() then) {
    if (_fadeLeft == 0) {
      _fadeLeft = _fadeFrames;
    }
    _afterFade = then;
  }

  void _cancelFade() {
    _fadeLeft = 0;
    _afterFade = null;
  }

  /// Renders [left] and [right] (their length), whose first frame is heard
  /// at [time] of the output clock.
  void render(Float32List left, Float32List right, double time) {
    var frames = left.length;
    if (_state != MidiPlayerState.playing) {
      left.fillRange(0, frames, 0);
      right.fillRange(0, frames, 0);
      return;
    }
    if (_untilReport <= 0) {
      _untilReport = reportFrames;
      send({
        'type': MidiHostEvents.position,
        'position': engine.position,
        'time': time,
        'speed': engine.speed,
        'seq': ?_seq,
      });
    }
    _untilReport -= frames;
    _mixdown.mix(engine.render(frames), left, right);
    if (_fadeLeft > 0) {
      for (var i = 0; i < frames; i++) {
        var gain = _fadeLeft > 0 ? _fadeLeft / _fadeFrames : 0.0;
        left[i] *= gain;
        right[i] *= gain;
        if (_fadeLeft > 0) {
          _fadeLeft--;
        }
      }
      if (_fadeLeft == 0) {
        var then = _afterFade;
        _afterFade = null;
        then?.call();
      }
      return;
    }
    if (engine.ended) {
      var timeline = engine.timeline!;
      engine.silence();
      engine.seek(timeline.start);
      _setState(MidiPlayerState.stopped);
    }
  }
}
