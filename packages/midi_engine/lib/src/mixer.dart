/// The mixer: a volume, a pan, mute and solo per track, then the master
/// gain and a limiter. Mixed in Dart (the stream output, offline) or by Web
/// Audio nodes, the same way.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';

import 'engine.dart';
import 'reverb.dart';
import 'timeline.dart';

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

  /// The send to the shared reverb, 0 (none, the default) to 1: after the
  /// volume, so a muted track sends nothing.
  double reverb;

  /// A mix.
  MidiTrackMix({
    this.volume = 1,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
    this.reverb = 0,
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

  /// The level of the shared reverb in the mix, 0 to 1 (1 by default: as the
  /// reverb of a SoundFont synth with its effects on). Heard only when a
  /// track sends to it ([MidiTrackMix.reverb]).
  var reverbLevel = 1.0;

  /// The send of [track] to the shared reverb, 0 when none.
  double reverbOf(int track) =>
      track < tracks.length ? tracks[track].reverb : 0;

  /// True when a track sends to the reverb.
  bool get hasReverb => tracks.any((track) => track.reverb > 0);

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

  /// The gain for a frame peaking at [peak].
  double _next(double peak) {
    var target = peak > limit ? limit / peak : 1.0;
    if (target < _gain) {
      _gain = target;
    } else {
      _gain += (target - _gain) * _release;
    }
    return _gain;
  }

  /// Limits [frames] (interleaved stereo) in place.
  void process(Float32List frames) {
    for (var i = 0; i < frames.length; i += 2) {
      var gain = _next(math.max(frames[i].abs(), frames[i + 1].abs()));
      frames[i] *= gain;
      frames[i + 1] *= gain;
    }
  }

  /// Limits [left] and [right] in place.
  void processStereo(Float32List left, Float32List right) {
    for (var i = 0; i < left.length; i++) {
      var gain = _next(math.max(left[i].abs(), right[i].abs()));
      left[i] *= gain;
      right[i] *= gain;
    }
  }
}

/// The mix of a track in a [MidiStereoMixdown]: its gain and its reverb
/// send move to their target over a block.
class _MixdownTrack {
  double gain;
  double target;
  double pan;
  var reverb = 0.0;
  var reverbTarget = 0.0;

  /// The peak since the last [MidiStereoMixdown.takePeaks].
  var peak = 0.0;

  _MixdownTrack(this.gain, this.pan) : target = gain;
}

/// Mixes rendered blocks down to stereo as they are played: a gain per track
/// moved to its new value over a block (no click), a pan, a send to the
/// shared reverb, the master gain and the limiter. It keeps the peak of
/// each track (the meters).
class MidiStereoMixdown {
  final _tracks = <_MixdownTrack>[];
  final MidiLimiter _limiter;
  final int _sampleRate;
  MidiReverbBus? _reverb;
  var _reverbLevel = 1.0;

  /// A mixdown at [sampleRate].
  MidiStereoMixdown({required int sampleRate})
    : _sampleRate = sampleRate,
      _limiter = MidiLimiter(sampleRate: sampleRate);

  _MixdownTrack _track(int track) {
    while (_tracks.length <= track) {
      _tracks.add(_MixdownTrack(1, 0));
    }
    return _tracks[track];
  }

  /// The [gain] and the [pan] of [track], heard from the next block (the
  /// first time: at once), and its send to the shared reverb, 0 to 1
  /// (unchanged when null, none at first).
  void setTrack(
    int track, {
    required double gain,
    required double pan,
    double? reverb,
  }) {
    var isNew = track >= _tracks.length;
    var mix = _track(track)
      ..target = gain
      ..pan = pan;
    if (isNew) {
      mix.gain = gain;
    }
    if (reverb != null) {
      mix.reverbTarget = reverb;
      if (isNew) {
        mix.reverb = reverb;
      }
      if (reverb > 0) {
        _reverb ??= MidiReverbBus(sampleRate: _sampleRate)
          ..level = _reverbLevel;
      }
    }
  }

  /// The level of the shared reverb in the mix, 0 to 1 (1 by default).
  double get reverbLevel => _reverbLevel;

  set reverbLevel(double level) {
    _reverbLevel = level;
    _reverb?.level = level;
  }

  /// True when the shared reverb is silent: nothing sent to it (or only
  /// silence), its tail over.
  bool get reverbIdle => _reverb?.idle ?? true;

  /// Silences the tail of the reverb at once (a pause, a stop).
  void silence() => _reverb?.mute();

  /// The peak level of each of the [trackCount] tracks since the last call
  /// (after their gain, before the pan, the master gain and the limiter),
  /// then every track starts again from 0.
  Float32List takePeaks(int trackCount) {
    var peaks = Float32List(trackCount);
    for (var (track, mix) in _tracks.indexed) {
      if (track < trackCount) {
        peaks[track] = mix.peak;
      }
      mix.peak = 0;
    }
    return peaks;
  }

  /// Mixes [block] into [left] and [right] (replacing what is there, of the
  /// block length).
  void mix(MidiRenderBlock block, Float32List left, Float32List right) {
    var frames = block.frames;
    left.fillRange(0, frames, 0);
    right.fillRange(0, frames, 0);
    var reverb = _reverb;
    Float32List? sends;
    var fed = false;
    for (var track = 0; track < block.trackCount; track++) {
      var mix = _track(track);
      var from = mix.gain;
      var to = mix.target;
      mix.gain = to;
      var sendFrom = mix.reverb * from;
      var sendTo = mix.reverbTarget * to;
      mix.reverb = mix.reverbTarget;
      if (from == 0 && to == 0) {
        continue;
      }
      var pan = midiStereoPan(mix.pan);
      var trackLeft = block.left[track];
      var trackRight = block.right[track];
      var peak = 0.0;
      // The gain (and the send) moves over the block, by a step a frame.
      var start = from * midiMasterGain;
      var step = (to - from) / frames * midiMasterGain;
      if (reverb != null && (sendFrom > 0 || sendTo > 0)) {
        if (!fed) {
          fed = true;
          sends = reverb.input(frames);
        }
        var input = sends!;
        var sendStart = sendFrom * midiMasterGain;
        var sendStep = (sendTo - sendFrom) / frames * midiMasterGain;
        for (var i = 0; i < frames; i++) {
          var a = trackLeft[i];
          var b = trackRight[i];
          var gain = start + step * i;
          var l = a * gain;
          var r = b * gain;
          left[i] += l * pan.leftToLeft + r * pan.rightToLeft;
          right[i] += l * pan.leftToRight + r * pan.rightToRight;
          input[i] += (a + b) * (sendStart + sendStep * i);
          if (a < 0) {
            a = -a;
          }
          if (b < 0) {
            b = -b;
          }
          if (a > peak) {
            peak = a;
          }
          if (b > peak) {
            peak = b;
          }
        }
      } else {
        for (var i = 0; i < frames; i++) {
          var a = trackLeft[i];
          var b = trackRight[i];
          var gain = start + step * i;
          var l = a * gain;
          var r = b * gain;
          left[i] += l * pan.leftToLeft + r * pan.rightToLeft;
          right[i] += l * pan.leftToRight + r * pan.rightToRight;
          if (a < 0) {
            a = -a;
          }
          if (b < 0) {
            b = -b;
          }
          if (a > peak) {
            peak = a;
          }
          if (b > peak) {
            peak = b;
          }
        }
      }
      peak *= from > to ? from : to;
      if (peak > mix.peak) {
        mix.peak = peak;
      }
    }
    if (reverb != null && reverb.process(frames, fed: fed)) {
      var level = reverb.level;
      var wetLeft = reverb.left;
      var wetRight = reverb.right;
      for (var i = 0; i < frames; i++) {
        left[i] += wetLeft[i] * level;
        right[i] += wetRight[i] * level;
      }
    }
    _limiter.processStereo(left, right);
  }
}

/// The default reverb send of General MIDI synths (CC 91 at 40, as
/// dart_melty_soundfont and GS synths).
const midiDefaultReverbSend = 40 / 127;

/// The send to the shared reverb of each of the [trackCount] tracks of
/// [timeline], from its reverb controller (CC 91, 0 to 127): the value set
/// at its first note (the last before it), else the first one it sets,
/// else [missing] ([midiDefaultReverbSend] by default); 0 for a track
/// without notes. For `setReverb`: the engine does not follow CC 91 itself.
List<double> midiReverbSends(
  MidiTimeline timeline, {
  required int trackCount,
  double missing = midiDefaultReverbSend,
}) {
  var firstNotes = List<double?>.filled(trackCount, null);
  for (var note in timeline.notes) {
    var track = note.track;
    if (track < trackCount) {
      var first = firstNotes[track];
      if (first == null || note.start < first) {
        firstNotes[track] = note.start;
      }
    }
  }
  var atFirstNote = List<int?>.filled(trackCount, null);
  var firstSet = List<int?>.filled(trackCount, null);
  for (var message in timeline.messages) {
    var track = message.track;
    if (track >= trackCount ||
        message.status & 0xf0 != midiControlChange ||
        message.data1 != midiControllerReverb) {
      continue;
    }
    firstSet[track] ??= message.data2;
    var first = firstNotes[track];
    if (first != null && message.time <= first) {
      atFirstNote[track] = message.data2;
    }
  }
  double send(int track) {
    if (firstNotes[track] == null) {
      return 0;
    }
    var value = atFirstNote[track] ?? firstSet[track];
    return value == null ? missing : value / 127;
  }

  return [for (var track = 0; track < trackCount; track++) send(track)];
}
