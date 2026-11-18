/// The SoundFont of each song, from a SoundFont kept whole (an SF3, its
/// samples compressed, or an SF2): only the samples the song plays, decoded
/// when first needed, kept for the next songs.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_vorbis/vorbis.dart';

import 'definition.dart';
import 'partial.dart';
import 'riff.dart';
import 'worker/protocol.dart';
import 'worker/sampler_io.dart'
    if (dart.library.js_interop) 'worker/sampler_web.dart';

/// The frames kept decoded by default, in bytes: the samples of a few
/// songs.
const midiSoundFontSamplerCacheBytes = 8 * 1024 * 1024;

/// Makes the SoundFont of a song from a SoundFont kept whole: the whole
/// definition (presets, instruments, zones, sample headers) and only the
/// samples asked, so that the engine holds the samples of the songs played
/// (1 to 3 MB of GeneralUser GS for a song) instead of all of them (32 MB),
/// and an SF3 is never decoded whole.
abstract class MidiSoundFontSampler {
  /// The definition of the SoundFont.
  MidiSoundFontDefinition get definition;

  /// The samples [timeline] plays at [transpose] (indexes in
  /// `definition.samples`), and at each transposition up to [margin]
  /// semitones from it: a transposition within the margin needs no other
  /// sample (about 1.4 times the samples for 12 semitones, the songs of
  /// GeneralUser GS).
  Set<int> samplesOf(
    MidiTimeline timeline, {
    int transpose = 0,
    int margin = 0,
  }) => {
    for (var t = transpose - margin; t <= transpose + margin; t++)
      ...definition.samplesFor(midiSoundFontNotes(timeline, transpose: t)),
  };

  /// An SF2 (its own buffer, to move to the engine) with the whole
  /// definition and [samples] only, decoded first when not kept; the other
  /// samples silent. A [FormatException] for a sample that does not decode.
  Future<Uint8List> soundFont(Iterable<int> samples);

  /// Stops it (the worker terminated, the samples kept released).
  Future<void> close();
}

/// A [MidiSoundFontSampler] in this isolate: the SoundFont [bytes] kept,
/// the samples decoded one after the other (the event loop runs every
/// [slice], a page stays responsive), the last used kept up to
/// [cacheBytes] of frames.
class MidiSoundFontLocalSampler extends MidiSoundFontSampler {
  final SoundFontChunk _bank;

  @override
  final MidiSoundFontDefinition definition;

  /// The bytes of frames kept decoded at most (the samples of the last
  /// SoundFont made always).
  final int cacheBytes;

  /// How long it decodes before letting the event loop run.
  final Duration slice;

  /// The frames decoded, the least recently used first.
  final _frames = <int, Int16List>{};
  var _cachedBytes = 0;
  final _setups = VorbisSetupCache();
  Future<void>? _last;

  MidiSoundFontLocalSampler._(
    this._bank,
    this.definition,
    this.cacheBytes,
    this.slice,
  );

  /// A sampler of the SoundFont [bytes] (SF2 or SF3), kept as they are: a
  /// [FormatException] when it is not a SoundFont.
  factory MidiSoundFontLocalSampler(
    Uint8List bytes, {
    int cacheBytes = midiSoundFontSamplerCacheBytes,
    Duration slice = const Duration(milliseconds: 16),
  }) {
    var bank = soundFontReadBank(bytes);
    return MidiSoundFontLocalSampler._(
      bank,
      MidiSoundFontDefinition.ofBank(bank),
      cacheBytes,
      slice,
    );
  }

  /// The samples kept decoded.
  Iterable<int> get decoded => _frames.keys;

  @override
  Future<Uint8List> soundFont(Iterable<int> samples) {
    // One after the other: two at once would decode a sample twice.
    var previous = _last;
    var result = () async {
      await previous;
      return _soundFont(samples.toSet());
    }();
    _last = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Uint8List> _soundFont(Set<int> samples) async {
    var count = definition.samples.length;
    var frames = <int, Int16List>{};
    var watch = Stopwatch()..start();
    for (var i in samples.toList()..sort()) {
      if (i < 0 || i >= count) {
        throw RangeError.range(i, 0, count - 1, 'sample');
      }
      var sample = _frames.remove(i);
      if (sample == null) {
        sample = soundFontSampleFrames(_bank, i, setups: _setups);
        _cachedBytes += sample.lengthInBytes;
        if (watch.elapsed >= slice) {
          await Future<void>.delayed(Duration.zero);
          watch.reset();
        }
      }
      // The most recently used last.
      _frames[i] = sample;
      frames[i] = sample;
    }
    _trim(samples);
    return soundFontWithSamples(
      _bank,
      frames,
      bound: definition.addressOffsetBound,
    );
  }

  /// Forgets the least recently used frames beyond [cacheBytes], but those
  /// of [keep].
  void _trim(Set<int> keep) {
    if (_cachedBytes <= cacheBytes) {
      return;
    }
    for (var i in _frames.keys.toList()) {
      if (_cachedBytes <= cacheBytes) {
        break;
      }
      if (!keep.contains(i)) {
        _cachedBytes -= _frames.remove(i)!.lengthInBytes;
      }
    }
  }

  @override
  Future<void> close() async {
    _frames.clear();
    _cachedBytes = 0;
  }
}

/// The sampler of an app: on the web in a web worker of its own running
/// the script at [url] (`sound_font_worker.js`, built by
/// `setupMidiSoundFontWorker`), for the session: [bytes] are moved to it
/// (empty here once it starts; with dart2wasm a copy is moved, [bytes] are
/// released once dropped), so the page holds the definition only; on io a
/// [MidiSoundFontLocalSampler].
///
/// When the worker does not start within [startTimeout] (the script
/// missing, built for another protocol), the sampler runs in the page when
/// [fallback] (a console warning), else a `MidiSoundFontWorkerException` is
/// thrown. A worker dying makes the next calls throw one: make another
/// sampler.
Future<MidiSoundFontSampler> midiSoundFontSampler(
  Uint8List bytes, {
  String url = midiSoundFontWorkerJsFilename,
  bool fallback = true,
  Duration startTimeout = const Duration(seconds: 30),
  int cacheBytes = midiSoundFontSamplerCacheBytes,
}) => newMidiSoundFontSampler(
  bytes,
  url: url,
  fallback: fallback,
  startTimeout: startTimeout,
  cacheBytes: cacheBytes,
);
