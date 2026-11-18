/// The audio output interface: blocks played at times of its own clock, a
/// gain and a pan per track. And an output with no sound.
library;

import 'engine.dart';

/// An audio output.
abstract class MidiAudioSink {
  /// The sample rate.
  int get sampleRate;

  /// The output clock, in seconds.
  double get currentTime;

  /// How far ahead of [currentTime] a block must start to be heard whole
  /// (what the output already holds), in seconds.
  double get startLatency;

  /// Makes the output ready (the web needs a user gesture first).
  Future<void> resume();

  /// Plays [block] at [when] (output clock).
  void schedule(double when, MidiRenderBlock block);

  /// Stops at once everything scheduled.
  void cancel();

  /// The [gain] and the [pan] (-1 to 1) of [track], heard at once when the
  /// output can.
  void setTrackMix(int track, {required double gain, required double pan});

  /// Closes the output.
  Future<void> close();
}

/// An output that also mixes the shared reverb of the tracks (in Dart):
/// `MidiPlayer` sends it the reverb of its mixer. The others play dry.
abstract interface class MidiReverbSink {
  /// The send of [track] to the shared reverb, 0 to 1, heard at once when
  /// the output can.
  void setTrackReverb(int track, double send);

  /// Sets the level of the shared reverb in the mix, 0 to 1.
  set reverbLevel(double level);
}

/// An output that also mixes the shared chorus of the tracks (in Dart):
/// `MidiPlayer` sends it the chorus of its mixer. The others play dry.
abstract interface class MidiChorusSink {
  /// The send of [track] to the shared chorus, 0 to 1, heard at once when
  /// the output can.
  void setTrackChorus(int track, double send);

  /// Sets the level of the shared chorus in the mix, 0 to 1.
  set chorusLevel(double level);
}

/// An output with no sound: its clock is a stopwatch (the tests, the
/// platforms without an output yet); it keeps the blocks when asked.
class MidiSilentSink implements MidiAudioSink, MidiReverbSink, MidiChorusSink {
  @override
  final int sampleRate;

  /// The clock, set by hand when given.
  final double Function()? clock;

  final _stopwatch = Stopwatch();

  /// The blocks scheduled, when [keep].
  final List<(double, MidiRenderBlock)> blocks = [];

  /// The gain and pan of each track set.
  final Map<int, (double, double)> mixes = {};

  /// The reverb send of each track set.
  final Map<int, double> reverbs = {};

  /// The level of the shared reverb set.
  @override
  var reverbLevel = 1.0;

  /// The chorus send of each track set.
  final Map<int, double> choruses = {};

  /// The level of the shared chorus set.
  @override
  var chorusLevel = 1.0;

  /// Keeps the blocks scheduled.
  final bool keep;

  /// A silent output.
  MidiSilentSink({this.sampleRate = 44100, this.clock, this.keep = false});

  @override
  double get currentTime =>
      clock?.call() ?? _stopwatch.elapsedMicroseconds / 1e6;

  @override
  double get startLatency => 0.04;

  @override
  Future<void> resume() async => _stopwatch.start();

  @override
  void schedule(double when, MidiRenderBlock block) {
    if (keep) {
      blocks.add((when, block));
    }
  }

  @override
  void cancel() {
    if (keep) {
      blocks.clear();
    }
  }

  @override
  void setTrackMix(int track, {required double gain, required double pan}) {
    mixes[track] = (gain, pan);
  }

  @override
  void setTrackReverb(int track, double send) {
    reverbs[track] = send;
  }

  @override
  void setTrackChorus(int track, double send) {
    choruses[track] = send;
  }

  @override
  Future<void> close() async => _stopwatch.stop();
}
