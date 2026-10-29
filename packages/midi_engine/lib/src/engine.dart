/// The engine (from accordelio's): plays a timeline on the audio clock.
/// Asked for N frames, it sends each event to the synth of its track at its
/// exact frame (splitting the synths' renders there), renders a stereo pair
/// of buffers per track (each mixed downstream with its own volume and pan),
/// and loops when asked.
library;

import 'dart:typed_data';

import 'package:tekartik_midi_synth/midi_synth.dart';

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
  /// rendered).
  double get speed => _speed;

  set speed(double speed) {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }
    _speed = speed;
  }

  /// The transposition, in semitones (heard from the next notes; the notes
  /// sounding are released on the key they were played on). The percussion
  /// channel is not transposed.
  var transpose = 0;

  /// Loads [timeline] at [position] (its start by default): the synths are
  /// reset.
  void load(MidiTimeline timeline, {double? position}) {
    _timeline = timeline;
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
    _seek(position);
  }

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
    if (message.track < synths.length) {
      synths[message.track].send(message.status, message.data1, message.data2);
    }
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
    return ((loopEnd - _position) / _speed * sampleRate).ceil();
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
