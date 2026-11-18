import 'dart:typed_data';

import '../sampler.dart';

/// On io: in the calling isolate.
Future<MidiSoundFontSampler> newMidiSoundFontSampler(
  Uint8List bytes, {
  required String url,
  required bool fallback,
  required Duration startTimeout,
  required int cacheBytes,
}) async => MidiSoundFontLocalSampler(bytes, cacheBytes: cacheBytes);
