/// The engine (from accordelio's): plays a timeline on the audio clock.
/// Asked for N frames, it sends each event to the synth of its track at its
/// exact frame (splitting the synths' renders there), renders a stereo pair
/// of buffers per track (each mixed downstream with its own volume and pan),
/// and loops when asked.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';

import 'speed_trainer.dart';
import 'timeline.dart';

/// The frames of a render, a stereo pair of buffers per track.
class MidiRenderBlock {
  /// The left buffers, by track.
  final List<Float32List> left;

  /// The right buffers, by track.
  final List<Float32List> right;

  /// The number of frames.
  final int frames;

  /// The song time of the first frame, in seconds.
  final double songStart;

  /// The song seconds played in a second (the speed).
  final double speed;

  /// A block.
  MidiRenderBlock(
    this.left,
    this.right,
    this.frames,
    this.songStart, {
    this.speed = 1,
  });

  /// The number of tracks.
  int get trackCount => left.length;
}

/// A note sounding: the key actually played (transposed), its end.
class _Sounding {
  final int track;
  final int channel;
  final int key;
  final double end;

  _Sounding(this.track, this.channel, this.key, this.end);
}

/// The engine.
class MidiEngine {
  /// The output sample rate.
  final int sampleRate;

  /// The synth of each track.
  final List<MidiSynth> synths;

  /// A note sounding where a seek or a loop goes is started again when it
  /// lasts at least this long after it, in seconds.
  static const restartMinimum = 0.08;

  MidiTimeline? _timeline;

  /// The song time of the next frame, in seconds.
  var _position = 0.0;

  /// The index of the next note to start.
  var _nextNote = 0;

  /// The index of the next message to send.
  var _nextMessage = 0;

  final _sounding = <_Sounding>[];

  double? _loopStart;
  double? _loopEnd;
  var _speed = 1.0;

  MidiSpeedTrainer? _trainer;

  /// The passes of the loop since the trainer was set.
  var _passes = 0;

  var _tuneCents = 0.0;

  /// True once tuned: the tuning is sent from then on.
  var _tuned = false;

  /// The melodic channels of the timeline, as `track * 16 + channel`: they
  /// get the tuning.
  var _tuneTargets = const <int>[];

  /// The RPN the timeline selected, by `track * 16 + channel`.
  final _songRpn = <int, int>{};

  /// The fine tuning (RPN 1) the timeline set, by `track * 16 + channel`.
  final _songFineTuning = <int, int>{};

  /// An engine at [sampleRate], [synths] playing the tracks (a timeline
  /// event on a track without a synth is ignored).
  MidiEngine({required this.sampleRate, required List<MidiSynth> synths})
    : synths = List.unmodifiable(synths) {
    for (var synth in synths) {
      if (synth.sampleRate != sampleRate) {
        throw ArgumentError.value(
          synth.sampleRate,
          'synths',
          'sample rate is not $sampleRate',
        );
      }
    }
  }

  /// The timeline played, null before [load].
  MidiTimeline? get timeline => _timeline;

  /// The song time of the next frame, in seconds.
  double get position => _position;

  /// The loop, null when none.
  (double, double)? get loop =>
      _loopStart == null ? null : (_loopStart!, _loopEnd!);

  /// The song seconds played in a second (heard from the next frame
  /// rendered). Setting it stops the [speedTrainer].
  double get speed => _speed;

  set speed(double speed) {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }
    _speed = speed;
    _trainer = null;
  }

  /// The speed trainer of the loop, null when none: setting one sets the
  /// speed to its `from` at once, then each time the loop starts again
  /// (every `everyPasses` passes) the speed takes its next step, from the
  /// frame of the loop start. Nothing changes without a loop.
  MidiSpeedTrainer? get speedTrainer => _trainer;

  set speedTrainer(MidiSpeedTrainer? trainer) {
    _trainer = trainer;
    _passes = 0;
    if (trainer != null) {
      _speed = trainer.from;
    }
  }

  /// The passes of the loop played since the [speedTrainer] was set.
  int get loopPasses => _passes;

  /// The transposition, in semitones (heard from the next notes; the notes
  /// sounding are released on the key they were played on). The percussion
  /// channel is not transposed.
  var transpose = 0;

  /// The tuning, in cents, -100 to 100 (0 by default), of the melodic
  /// channels (not the percussion channel): a fine tuning (RPN 1) sent to
  /// each of them, and again after each seek (whose reset of the
  /// controllers resets it), heard at once by the SoundFont synth, from the
  /// next notes by the Dart synths. A fine tuning set by the timeline itself
  /// gets the sum. Until set, nothing is sent.
  double get tuneCents => _tuneCents;

  set tuneCents(double cents) {
    if (!cents.isFinite || cents < -100 || cents > 100) {
      throw ArgumentError.value(cents, 'tuneCents', 'must be -100 to 100');
    }
    _tuneCents = cents;
    if (cents != 0) {
      _tuned = true;
    }
    _sendTune();
  }

  /// Loads [timeline] at [position] (its start by default): the synths are
  /// reset.
  void load(MidiTimeline timeline, {double? position}) {
    _timeline = timeline;
    _tuneTargets = _melodicChannels(timeline);
    _sounding.clear();
    for (var synth in synths) {
      synth.reset();
    }
    _seek(position ?? timeline.start);
  }

  /// Plays [timeline] in place of the current one from the same place
  /// ([at], the current position by default), keeping the loop: the notes
  /// sounding there are started again (an edit).
  void replace(MidiTimeline timeline, {double? at}) {
    var position = at ?? _position;
    _releaseAll();
    _timeline = timeline;
    _tuneTargets = _melodicChannels(timeline);
    _seek(position);
  }

  /// The melodic channels of [timeline] with a synth, as
  /// `track * 16 + channel`.
  List<int> _melodicChannels(MidiTimeline timeline) {
    var channels = <int>{
      for (var note in timeline.notes)
        if (note.channel != midiPercussionChannel && note.track < synths.length)
          note.track * 16 + note.channel,
      for (var message in timeline.messages)
        if (message.channel != midiPercussionChannel &&
            message.track < synths.length)
          message.track * 16 + message.channel,
    };
    return channels.toList()..sort();
  }

  /// Sends the tuning to the melodic channels of the timeline (with the
  /// timeline's own fine tuning), then selects the RPN the timeline had
  /// selected again.
  void _sendTune() {
    if (!_tuned) {
      return;
    }
    var offset = midiFineTuningValue(_tuneCents) - 8192;
    for (var target in _tuneTargets) {
      var synth = synths[target >> 4];
      var status = midiControlChange | (target & 0x0f);
      var value = ((_songFineTuning[target] ?? 8192) + offset).clamp(0, 16383);
      var rpn = _songRpn[target] ?? midiRpnNull;
      synth
        ..send(status, midiControllerRpnMsb, 0)
        ..send(status, midiControllerRpnLsb, midiRpnFineTuning)
        ..send(status, midiControllerDataEntry, value >> 7)
        ..send(status, midiControllerDataEntryLsb, value & 0x7f)
        ..send(status, midiControllerRpnMsb, rpn >> 7)
        ..send(status, midiControllerRpnLsb, rpn & 0x7f);
    }
  }

  /// The notes sounding (started, not released yet): their track, their
  /// channel and the key played (transposed).
  List<({int track, int channel, int key})> get soundingNotes => [
    for (var sounding in _sounding)
      (track: sounding.track, channel: sounding.channel, key: sounding.key),
  ];

  /// Loops from [start] to [end] (song seconds), null to stop looping.
  void setLoop(double? start, double? end) {
    if (start == null || end == null || end <= start) {
      _loopStart = null;
      _loopEnd = null;
    } else {
      _loopStart = start;
      _loopEnd = end;
    }
  }

  /// Goes to [position] (song seconds): every note is released, the
  /// messages before it are sent again, the notes sounding there are
  /// started again.
  void seek(double position) {
    _releaseAll();
    _seek(position);
  }

  /// Releases every note (a pause).
  void releaseAll() => _releaseAll();

  /// Silences every synth at once, their releases too (all sound off on
  /// every channel): before a seek when nothing plays, so that no release
  /// is heard when playing again.
  void silence() {
    _sounding.clear();
    for (var synth in synths) {
      for (var channel = 0; channel < 16; channel++) {
        synth.send(midiControlChange | channel, midiControllerAllSoundOff);
      }
    }
  }

  void _releaseAll() {
    for (var sounding in _sounding) {
      synths[sounding.track].send(midiNoteOff | sounding.channel, sounding.key);
    }
    _sounding.clear();
  }

  void _seek(double position) {
    _position = position;
    var timeline = _timeline;
    if (timeline == null) {
      _nextNote = 0;
      _nextMessage = 0;
      return;
    }
    var notes = timeline.notes;
    var messages = timeline.messages;
    _nextNote = _firstAtOrAfter(notes.length, (i) => notes[i].start, position);
    _nextMessage = _firstAtOrAfter(
      messages.length,
      (i) => messages[i].time,
      position,
    );
    // The channel state there: the channels the timeline sets are reset,
    // then its messages before the position are sent again.
    _songRpn.clear();
    _songFineTuning.clear();
    if (messages.isNotEmpty) {
      var channels = <(int, int)>{
        for (var message in messages) (message.track, message.channel),
      };
      for (var (track, channel) in channels) {
        if (track < synths.length) {
          synths[track]
            ..send(midiControlChange | channel, midiControllerResetAll)
            ..send(
              midiControlChange | channel,
              midiControllerVolume,
              midiDefaultVolume,
            )
            ..send(midiControlChange | channel, midiControllerPan, 64)
            ..send(midiProgramChange | channel, 0);
        }
      }
      for (var i = 0; i < _nextMessage; i++) {
        _send(messages[i]);
      }
    }
    _sendTune();
    for (var i = 0; i < _nextNote; i++) {
      var note = notes[i];
      if (note.end - position >= restartMinimum) {
        _noteOn(note);
      }
    }
  }

  /// The first index whose time is at or after [position].
  static int _firstAtOrAfter(
    int length,
    double Function(int index) time,
    double position,
  ) {
    var low = 0;
    var high = length;
    while (low < high) {
      var mid = (low + high) >> 1;
      if (time(mid) < position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _send(MidiTimelineMessage message) {
    var track = message.track;
    if (track >= synths.length) {
      return;
    }
    var status = message.status;
    if (status & 0xf0 == midiControlChange) {
      // Follows the RPN and the fine tuning set by the timeline: tuned, the
      // fine tuning sent is the sum.
      var target = track * 16 + (status & 0x0f);
      var value = message.data2;
      switch (message.data1) {
        case midiControllerRpnMsb:
          _songRpn[target] =
              ((_songRpn[target] ?? midiRpnNull) & 0x7f) | (value << 7);
        case midiControllerRpnLsb:
          _songRpn[target] =
              ((_songRpn[target] ?? midiRpnNull) & 0x3f80) | value;
        case midiControllerResetAll:
          _songRpn.remove(target);
          _songFineTuning.remove(target);
        case midiControllerDataEntry || midiControllerDataEntryLsb
            when _songRpn[target] == midiRpnFineTuning:
          var fine = _songFineTuning[target] ?? 8192;
          fine = message.data1 == midiControllerDataEntry
              ? (fine & 0x7f) | (value << 7)
              : (fine & 0x3f80) | value;
          _songFineTuning[target] = fine;
          if (_tuned && message.channel != midiPercussionChannel) {
            var tuned = (fine + midiFineTuningValue(_tuneCents) - 8192).clamp(
              0,
              16383,
            );
            synths[track]
              ..send(status, midiControllerDataEntry, tuned >> 7)
              ..send(status, midiControllerDataEntryLsb, tuned & 0x7f);
            return;
          }
      }
    }
    synths[track].send(status, message.data1, message.data2);
  }

  void _noteOn(MidiTimelineNote note) {
    if (note.track >= synths.length) {
      return;
    }
    var key = note.channel == midiPercussionChannel
        ? note.key
        : (note.key + transpose).clamp(0, 127);
    var synth = synths[note.track];
    // The same key again before its end: released first.
    _sounding.removeWhere((sounding) {
      if (sounding.track == note.track &&
          sounding.channel == note.channel &&
          sounding.key == key) {
        synth.send(midiNoteOff | note.channel, key);
        return true;
      }
      return false;
    });
    synth.send(midiNoteOn | note.channel, key, note.velocity);
    _sounding.add(_Sounding(note.track, note.channel, key, note.end));
  }

  /// True when everything was played (no loop) and every synth is silent.
  bool get ended {
    var timeline = _timeline;
    if (timeline == null) {
      return true;
    }
    return _loopStart == null &&
        _nextNote >= timeline.notes.length &&
        _nextMessage >= timeline.messages.length &&
        _position >= timeline.end &&
        _sounding.isEmpty &&
        synths.every((synth) => synth.activeVoiceCount == 0);
  }

  /// The frames rendered before the loop jumps back, null without a loop
  /// ahead.
  int? get framesToLoopEnd {
    var loopEnd = _loopEnd;
    if (loopEnd == null || _position >= loopEnd) {
      return null;
    }
    // The position adds up the blocks rendered: rounding errors must not
    // make the loop one frame longer. The loop jumps back within half a
    // frame of its end (render): the same frame whatever the block size.
    return ((loopEnd - _position) / _speed * sampleRate - 0.5).ceil();
  }

  /// Renders [frames] frames: the events due are sent at their frame, the
  /// loop jumps back at its end.
  MidiRenderBlock render(int frames) {
    var left = [for (var _ in synths) Float32List(frames)];
    var right = [for (var _ in synths) Float32List(frames)];
    var songStart = _position;
    var speed = _speed;
    var done = 0;
    while (done < frames) {
      var count = frames - done;
      var toLoop = framesToLoopEnd;
      if (toLoop != null && toLoop < count) {
        count = toLoop < 1 ? 1 : toLoop;
      }
      _renderSpan(left, right, done, count);
      done += count;
      var loopEnd = _loopEnd;
      if (loopEnd != null && _position >= loopEnd - 0.5 * _speed / sampleRate) {
        _releaseAll();
        _seek(_loopStart!);
        // The trainer's step, from the frame of the loop start.
        var trainer = _trainer;
        if (trainer != null) {
          _passes++;
          _speed = trainer.speedAfter(_passes);
        }
      }
    }
    return MidiRenderBlock(left, right, frames, songStart, speed: speed);
  }

  /// The time of the next event: a note off, a message, a note on.
  double _nextEventTime() {
    var time = double.infinity;
    for (var sounding in _sounding) {
      if (sounding.end < time) {
        time = sounding.end;
      }
    }
    var timeline = _timeline;
    if (timeline != null) {
      if (_nextMessage < timeline.messages.length) {
        var next = timeline.messages[_nextMessage].time;
        if (next < time) {
          time = next;
        }
      }
      if (_nextNote < timeline.notes.length) {
        var next = timeline.notes[_nextNote].start;
        if (next < time) {
          time = next;
        }
      }
    }
    return time;
  }

  /// Sends the events at [time]: the note offs, the messages, the note ons.
  void _dispatch(double time) {
    _sounding.removeWhere((sounding) {
      if (sounding.end <= time) {
        synths[sounding.track].send(
          midiNoteOff | sounding.channel,
          sounding.key,
        );
        return true;
      }
      return false;
    });
    var timeline = _timeline;
    if (timeline == null) {
      return;
    }
    var messages = timeline.messages;
    while (_nextMessage < messages.length &&
        messages[_nextMessage].time <= time) {
      _send(messages[_nextMessage++]);
    }
    var notes = timeline.notes;
    while (_nextNote < notes.length && notes[_nextNote].start <= time) {
      _noteOn(notes[_nextNote++]);
    }
  }

  void _renderSpan(
    List<Float32List> left,
    List<Float32List> right,
    int offset,
    int count,
  ) {
    var start = _position;
    var step = _speed / sampleRate;
    var end = start + count * step;
    // The events at the loop end belong to the next pass.
    var loopEnd = _loopEnd;
    var eventsEnd = loopEnd != null && start < loopEnd && loopEnd < end
        ? loopEnd
        : end;
    var done = 0;
    while (true) {
      var time = _nextEventTime();
      if (time >= eventsEnd) {
        break;
      }
      var at = ((time - start) / step).round().clamp(done, count);
      if (at > done) {
        _renderSynths(left, right, offset + done, at - done);
        done = at;
      }
      _dispatch(time);
    }
    if (done < count) {
      _renderSynths(left, right, offset + done, count - done);
    }
    _position = end;
  }

  void _renderSynths(
    List<Float32List> left,
    List<Float32List> right,
    int offset,
    int count,
  ) {
    for (var track = 0; track < synths.length; track++) {
      synths[track].render(left[track], right[track], offset, count);
    }
  }
}
