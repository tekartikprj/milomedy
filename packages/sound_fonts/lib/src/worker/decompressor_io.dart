import '../sf3.dart';
import 'decompressor.dart';

/// On io: in the calling isolate.
MidiSoundFontDecompressor newMidiSoundFontDecompressor({
  required String url,
  required bool fallback,
  required Duration startTimeout,
}) =>
    (bytes, {onProgress}) =>
        midiSoundFontDecompress(bytes, onProgress: onProgress);
