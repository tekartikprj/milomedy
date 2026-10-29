/// The mixer: a volume, a pan, mute and solo per track, then the master
/// gain and a limiter. Mixed in Dart (the stream output, offline) or by Web
/// Audio nodes, the same way.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'engine.dart';

/// The gain after the mix, before the limiter.
const midiMasterGain = 0.9;

/// The level the limiter keeps the peaks under.
const midiLimit = 0.7;

/// The mix of a track.
class MidiTrackMix {
  /// The volume, 0 to 1.
  double volume;

  /// The pan, -1 (left) to 1 (right).
  double pan;

  /// Muted.
  bool mute;

  /// Soloed.
  bool solo;

  /// A mix.
  MidiTrackMix({
    this.volume = 1,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
  });
}

/// The mix of the tracks.
class MidiMixer {
  /// The tracks.
  final List<MidiTrackMix> tracks;

  /// A mixer of [trackCount] tracks.
  MidiMixer(int trackCount)
    : tracks = [for (var i = 0; i < trackCount; i++) MidiTrackMix()];

  /// A mixer of [tracks].
  MidiMixer.of(this.tracks);

  /// The gain of [track]: its volume, 0 when muted or when other tracks are
  /// soloed.
  double gainOf(int track) {
    if (track >= tracks.length) {
      return 1;
    }
    var mix = tracks[track];
    if (mix.mute) {
      return 0;
    }
    if (!mix.solo && tracks.any((other) => other.solo)) {
      return 0;
    }
    return mix.volume;
  }

  /// The pan of [track].
  double panOf(int track) => track < tracks.length ? tracks[track].pan : 0;
}

/// The pan of a stereo input, as a Web Audio StereoPannerNode: the left
/// output is `left * leftToLeft + right * rightToLeft`, the right output is
/// `left * leftToRight + right * rightToRight`. In the middle, unchanged.
({
  double leftToLeft,
  double rightToLeft,
  double leftToRight,
  double rightToRight,
})
midiStereoPan(double pan) {
  var clamped = pan.clamp(-1.0, 1.0);
  if (clamped <= 0) {
    var x = (clamped + 1) * math.pi / 2;
    return (
      leftToLeft: 1,
      rightToLeft: math.cos(x),
      leftToRight: 0,
      rightToRight: math.sin(x),
    );
  }
  var x = clamped * math.pi / 2;
  return (
    leftToLeft: math.cos(x),
    rightToLeft: 0,
    leftToRight: math.sin(x),
    rightToRight: 1,
  );
}

/// [block] mixed to interleaved stereo with [mixer], times [masterGain].
Float32List midiMixStereo(
  MidiRenderBlock block,
  MidiMixer mixer, {
  double masterGain = 1,
}) {
  var out = Float32List(block.frames * 2);
  for (var track = 0; track < block.trackCount; track++) {
    var gain = mixer.gainOf(track) * masterGain;
    if (gain == 0) {
      continue;
    }
    var pan = midiStereoPan(mixer.panOf(track));
    var left = block.left[track];
    var right = block.right[track];
    for (var i = 0; i < block.frames; i++) {
      var l = left[i] * gain;
      var r = right[i] * gain;
      out[2 * i] += l * pan.leftToLeft + r * pan.rightToLeft;
      out[2 * i + 1] += l * pan.leftToRight + r * pan.rightToRight;
    }
  }
  return out;
}

/// Keeps the peaks of interleaved stereo under [limit]: the gain drops at
/// once, comes back in about 0.1 s.
class MidiLimiter {
  /// The level kept under.
  final double limit;

  final double _release;
  var _gain = 1.0;

  /// A limiter at [sampleRate].
  MidiLimiter({required int sampleRate, this.limit = midiLimit})
    : _release = 1 - math.exp(-1 / (0.1 * sampleRate));

  /// Limits [frames] (interleaved stereo) in place.
  void process(Float32List frames) {
    for (var i = 0; i < frames.length; i += 2) {
      var peak = math.max(frames[i].abs(), frames[i + 1].abs());
      var target = peak > limit ? limit / peak : 1.0;
      if (target < _gain) {
        _gain = target;
      } else {
        _gain += (target - _gain) * _release;
      }
      frames[i] *= _gain;
      frames[i + 1] *= _gain;
    }
  }
}
