/// What every player offers, wherever its engine runs: [MidiPlayer] on the
/// main isolate, `MidiWorkletPlayer` in an AudioWorklet.
library;

import 'timeline.dart';

/// The states of a player.
enum MidiPlayerState {
  /// At the start (or after the end).
  stopped,

  /// Playing.
  playing,

  /// Paused somewhere.
  paused,
}

/// A player of timelines: play, pause, seek, loop, speed, transpose, and the
/// mix of its tracks.
abstract interface class MidiTransport {
  /// The state.
  MidiPlayerState get state;

  /// The state and its changes.
  Stream<MidiPlayerState> get onState;

  /// True while playing.
  bool get isPlaying;

  /// The timeline played, null before [load].
  MidiTimeline? get timeline;

  /// Loads [timeline], stopped at its start.
  void load(MidiTimeline timeline);

  /// Plays [timeline] instead of the current one from the same place (an
  /// edit): heard at once.
  void replace(MidiTimeline timeline);

  /// The song time heard now, in seconds.
  double get position;

  /// Sets the volume of [track], 0 to 1.
  void setVolume(int track, double volume);

  /// Sets the pan of [track], -1 to 1.
  void setPan(int track, double pan);

  /// Mutes [track] or not.
  void setMute(int track, bool mute);

  /// Solos [track] or not.
  void setSolo(int track, bool solo);

  /// The song seconds played in a second.
  double get speed;

  /// Sets the speed: heard at once, from the same place.
  set speed(double speed);

  /// The transposition, in semitones.
  int get transpose;

  /// Sets the transposition: heard at once.
  set transpose(int transpose);

  /// Loops from [start] to [end] (song seconds), null for no loop.
  void setLoop(double? start, double? end);

  /// Plays from where it is (from the start after the end).
  Future<void> play();

  /// Pauses where it is.
  void pause();

  /// Stops and goes back to the start.
  void stop();

  /// Goes to [position] (song seconds).
  void seek(double position);

  /// Stops and closes the output.
  Future<void> close();
}
