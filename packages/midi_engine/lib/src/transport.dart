/// What every player offers, wherever its engine runs: [MidiPlayer] on the
/// main isolate, `MidiWorkletPlayer` in an AudioWorklet.
library;

import 'speed_trainer.dart';
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

  /// The tuning of the melodic channels (not the percussion channel), in
  /// cents, -100 to 100 (an [ArgumentError] otherwise), 0 by default: A4 at
  /// 442 Hz is about +7.85 cents. The SoundFont synth gets it as a fine
  /// tuning (RPN 1, heard at once), the Dart synths as a frequency factor
  /// (heard from their next notes).
  double get tuneCents;

  /// Sets the tuning.
  set tuneCents(double cents);

  /// Sets the send of [track] to the shared reverb, 0 (none, the default)
  /// to 1, after its volume. The app sets it (from the CC 91 of the file
  /// with `midiReverbSends`, or a control of its own): the CC 91 messages
  /// of the timeline only reach the synths (a SoundFont synth with its own
  /// effects).
  void setReverb(int track, double send);

  /// The level of the shared reverb in the mix, 0 to 1 (1 by default, as
  /// the reverb of a SoundFont synth with its effects on).
  double get reverbLevel;

  /// Sets the level of the shared reverb.
  set reverbLevel(double level);

  /// Sets the send of [track] to the shared chorus, 0 (none, the default)
  /// to 1, after its volume and pan. The app sets it (from the CC 93 of the
  /// file with `midiChorusSends`, or a control of its own), as the reverb.
  void setChorus(int track, double send);

  /// The level of the shared chorus in the mix, 0 to 1 (1 by default, as
  /// the chorus of a SoundFont synth with its effects on).
  double get chorusLevel;

  /// Sets the level of the shared chorus.
  set chorusLevel(double level);

  /// The speed trainer of the loop, null when none.
  MidiSpeedTrainer? get speedTrainer;

  /// Trains on the loop: the speed is [from] at once, then each time the
  /// loop starts again (every [everyPasses] passes) it takes a [step] toward
  /// [to], from the frame of the loop start, until [to]. The [speed]
  /// follows. Setting the [speed] stops it, so does [clearSpeedTrainer].
  void setSpeedTrainer({
    required double from,
    required double to,
    required double step,
    int everyPasses = 1,
  });

  /// Stops the speed trainer: the speed stays where it is.
  void clearSpeedTrainer();

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
