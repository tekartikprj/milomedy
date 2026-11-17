/// The engine host: runs an engine where the audio is made (an AudioWorklet,
/// later an isolate), driven by the messages of `protocol.dart`. It renders
/// the frames the output asks for, mixed, and reports its state and its
/// position. Nothing is rendered ahead: a command is heard from the next
/// block.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';

import 'engine.dart';
import 'meters.dart';
import 'mixer.dart';
import 'protocol.dart';
import 'sound_font_support.dart';
import 'speed_trainer.dart';
import 'synth_spec.dart';
import 'transport.dart';

/// The host.
class MidiEngineHost {
  /// The sample rate.
  final int sampleRate;

  /// The engine.
  final MidiEngine engine;

  /// The spec of each track.
  final List<MidiSynthSpec> specs;

  /// The SoundFonts loaded, by id.
  final _soundFonts = <String, Object>{};

  /// Sends an event to the player.
  final void Function(Map<String, Object?> event) send;

  /// The frames between two position reports (with the meters): about 30
  /// a second by default.
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

  /// A host of the synths of [synths] at [sampleRate], reporting its
  /// position every [reportFrames] frames (`sampleRate / 30` by default).
  MidiEngineHost({
    required this.sampleRate,
    required List<MidiSynthSpec> synths,
    required this.send,
    int? reportFrames,
  }) : specs = List.unmodifiable(synths),
       reportFrames = reportFrames ?? (sampleRate / 30).ceil(),
       engine = MidiEngine(
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
    // The meters start again.
    _mixdown.takePeaks(0);
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
        _mixdown.silence();
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
          _silence();
          engine.seek(timeline.start);
        }
        _setState(MidiPlayerState.playing);
      case MidiHostCommands.pause:
        if (_state == MidiPlayerState.playing) {
          var at = engine.position;
          _fadeOut(() {
            _silence();
            engine.seek(at);
            _setState(MidiPlayerState.paused);
          });
        }
      case MidiHostCommands.stop:
        void stop() {
          _silence();
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
          if (_fadeLeft > 0) {
            // A pause or a stop fading out: it ends paused there.
            _afterFade = () {
              _silence();
              engine.seek(position);
              _setState(MidiPlayerState.paused);
            };
          }
        } else {
          _silence();
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
      case MidiHostCommands.speedTrainer:
        var trainer = command['trainer'] as Map?;
        engine.speedTrainer = trainer == null
            ? null
            : MidiSpeedTrainer.fromMap(trainer);
        _untilReport = 0;
      case MidiHostCommands.tune:
        // Heard at once by the SoundFont synth, from the next notes by the
        // Dart synths: no resync, which would start the notes again.
        engine.tuneCents = number('value');
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
            reverb: values.length > 2 ? values[2].toDouble() : null,
          );
        }
        var reverb = command['reverb'] as num?;
        if (reverb != null) {
          _mixdown.reverbLevel = reverb.toDouble();
        }
      case MidiHostCommands.synth:
        var track = (command['track'] as num).toInt();
        var synth = engine.synths[track];
        if (synth is DartSynth) {
          MidiSynthSpec.fromMap(command['spec'] as Map).applyTo(synth);
          _resync();
        }
      case MidiHostCommands.soundFont:
        _loadSoundFont(command['id'] as String, command['bytes'] as Uint8List);
      case MidiHostCommands.sync:
        send({'type': MidiHostEvents.sync, 'id': command['id']});
      default:
        throw ArgumentError.value(command['type'], 'type', 'unknown command');
    }
  }

  /// Parses [bytes] (with the registered support) and gives the tracks
  /// playing SoundFont [id] their synth, set as before (the messages before
  /// the position sent again).
  void _loadSoundFont(String id, Uint8List bytes) {
    var support = midiSoundFontSupport;
    if (support == null) {
      throw StateError(
        'no SoundFont support here: register it '
        '(milomedy_midi_synth_sf2 midiSoundFontRegister())',
      );
    }
    var soundFont = _soundFonts[id] = support.parse(bytes);
    for (var (track, spec) in specs.indexed) {
      var synth = engine.synths[track];
      if (spec.soundFont == id && synth is MidiDeferredSynth) {
        synth.synth = support.synth(
          soundFont,
          sampleRate,
          effects: spec.effects,
        );
      }
    }
    if (_state == MidiPlayerState.playing) {
      _resync();
    } else {
      _silence();
      engine.seek(engine.position);
    }
  }

  /// Silences the synths and the reverb at once.
  void _silence() {
    engine.silence();
    _mixdown.silence();
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
        ...midiMetersEventFields(
          _mixdown.takePeaks(engine.synths.length),
          engine.soundingNotes,
        ),
      });
    }
    _untilReport -= frames;
    var speed = engine.speed;
    _mixdown.mix(engine.render(frames), left, right);
    if (engine.speed != speed) {
      // A step of the speed trainer: told with the next block.
      _untilReport = 0;
    }
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
    // The end, once the tail of the reverb is over too.
    if (engine.ended && _mixdown.reverbIdle) {
      var timeline = engine.timeline!;
      _silence();
      engine.seek(timeline.start);
      _setState(MidiPlayerState.stopped);
    }
  }
}
