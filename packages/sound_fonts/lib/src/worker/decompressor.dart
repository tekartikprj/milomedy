/// SF3 decompression out of the page's thread: in a web worker
/// (`sound_font_worker.js`), each SF3 in a worker of its own, terminated
/// once done (its memory released at once, none of it in the page's heap).
library;

import 'dart:typed_data';

import 'decompressor_io.dart'
    if (dart.library.js_interop) 'decompressor_web.dart';
import 'protocol.dart';

/// Turns the SF3 [bytes] into its SF2 (an SF2 is returned as is),
/// [onProgress] telling the samples done out of all: what
/// `midiSoundFontDecompress` does, here or elsewhere.
typedef MidiSoundFontDecompressor =
    Future<Uint8List> Function(
      Uint8List bytes, {
      void Function(int done, int total)? onProgress,
    });

/// The worker failed (it could not start, or died while decompressing: out
/// of memory?): the file is not the cause.
class MidiSoundFontWorkerException implements Exception {
  /// What failed.
  final String message;

  /// The worker failed.
  MidiSoundFontWorkerException(this.message);

  @override
  String toString() => 'MidiSoundFontWorkerException: $message';
}

/// The decompressor of an app: on the web, a web worker running the script
/// at [url] (`sound_font_worker.js` next to the page, built by
/// `setupMidiSoundFontWorker`); on io, `midiSoundFontDecompress` in the
/// calling isolate (its event loop running between the samples).
///
/// When the worker does not start within [startTimeout] (the script
/// missing, built for another protocol), the SF3 is decompressed in the page
/// when [fallback] (a console warning), else a
/// [MidiSoundFontWorkerException] is thrown. A worker dying while it
/// decompresses throws one too. The bytes given are kept (a copy goes to
/// the worker).
MidiSoundFontDecompressor midiSoundFontWorkerDecompressor({
  String url = midiSoundFontWorkerJsFilename,
  bool fallback = true,
  Duration startTimeout = const Duration(seconds: 30),
}) => newMidiSoundFontDecompressor(
  url: url,
  fallback: fallback,
  startTimeout: startTimeout,
);
