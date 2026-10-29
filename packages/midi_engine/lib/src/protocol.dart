/// The messages between a player and an engine host (an AudioWorklet, later
/// an isolate): maps of numbers, strings and typed lists, which a
/// MessagePort and a SendPort both carry.
library;

import 'dart:typed_data';

import 'timeline.dart';

/// The commands, from the player to the host.
abstract final class MidiHostCommands {
  /// Loads a timeline (`timeline`), stopped at its start.
  static const load = 'load';

  /// Plays a timeline (`timeline`) in place of the current one, at `at` or
  /// the same place.
  static const replace = 'replace';

  /// Plays.
  static const play = 'play';

  /// Pauses.
  static const pause = 'pause';

  /// Stops and goes back to the start.
  static const stop = 'stop';

  /// Goes to `position`.
  static const seek = 'seek';

  /// Loops from `start` to `end`, no loop when null.
  static const loop = 'loop';

  /// Sets the speed (`value`).
  static const speed = 'speed';

  /// Sets the transposition (`value`).
  static const transpose = 'transpose';

  /// Sets the gain and pan of the tracks (`tracks`: a list of
  /// `[gain, pan]`).
  static const mix = 'mix';

  /// Sets the synth of `track` (`spec`).
  static const synth = 'synth';

  /// Answered with a `sync` event of the same `id` once the commands before
  /// it are handled.
  static const sync = 'sync';
}

/// The events, from the host to the player.
abstract final class MidiHostEvents {
  /// The state changed (`state`, `position`).
  static const state = 'state';

  /// The song `position` at `time` of the output clock, playing at `speed`.
  static const position = 'position';

  /// The answer to a `sync` command (`id`).
  static const sync = 'sync';

  /// A command failed (`message`).
  static const error = 'error';
}

/// [timeline] as a map of typed lists.
Map<String, Object?> midiTimelineToMap(MidiTimeline timeline) {
  var notes = timeline.notes;
  var messages = timeline.messages;
  return {
    'start': timeline.start,
    'end': timeline.end,
    'notes': {
      'start': Float64List.fromList([for (var note in notes) note.start]),
      'duration': Float64List.fromList([for (var note in notes) note.duration]),
      'track': Int32List.fromList([for (var note in notes) note.track]),
      'channel': Uint8List.fromList([for (var note in notes) note.channel]),
      'key': Uint8List.fromList([for (var note in notes) note.key]),
      'velocity': Uint8List.fromList([for (var note in notes) note.velocity]),
    },
    'messages': {
      'time': Float64List.fromList([
        for (var message in messages) message.time,
      ]),
      'track': Int32List.fromList([
        for (var message in messages) message.track,
      ]),
      'status': Uint8List.fromList([
        for (var message in messages) message.status,
      ]),
      'data1': Uint8List.fromList([
        for (var message in messages) message.data1,
      ]),
      'data2': Uint8List.fromList([
        for (var message in messages) message.data2,
      ]),
    },
  };
}

/// The timeline of [map] (from [midiTimelineToMap]).
MidiTimeline midiTimelineFromMap(Map<Object?, Object?> map) {
  var notes = map['notes'] as Map;
  var messages = map['messages'] as Map;
  List<num> list(Map map, String key) => (map[key] as List).cast<num>();
  var starts = list(notes, 'start');
  var durations = list(notes, 'duration');
  var noteTracks = list(notes, 'track');
  var channels = list(notes, 'channel');
  var keys = list(notes, 'key');
  var velocities = list(notes, 'velocity');
  var times = list(messages, 'time');
  var messageTracks = list(messages, 'track');
  var statuses = list(messages, 'status');
  var data1 = list(messages, 'data1');
  var data2 = list(messages, 'data2');
  return MidiTimeline(
    notes: [
      for (var i = 0; i < starts.length; i++)
        MidiTimelineNote(
          start: starts[i].toDouble(),
          duration: durations[i].toDouble(),
          track: noteTracks[i].toInt(),
          channel: channels[i].toInt(),
          key: keys[i].toInt(),
          velocity: velocities[i].toInt(),
        ),
    ],
    messages: [
      for (var i = 0; i < times.length; i++)
        MidiTimelineMessage(
          time: times[i].toDouble(),
          track: messageTracks[i].toInt(),
          status: statuses[i].toInt(),
          data1: data1[i].toInt(),
          data2: data2[i].toInt(),
        ),
    ],
    start: (map['start'] as num).toDouble(),
    end: (map['end'] as num).toDouble(),
  );
}
