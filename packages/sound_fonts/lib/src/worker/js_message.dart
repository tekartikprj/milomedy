/// The messages between the page and the SoundFont worker, as JS objects
/// (web only; see `protocol.dart`).
library;

import 'dart:js_interop';

/// A message, a plain JS object with the fields of its type only.
extension type MidiSoundFontWorkerJsMessage._(JSObject _) implements JSObject {
  /// A message with the given fields only.
  external factory MidiSoundFontWorkerJsMessage({
    String type,
    int version,
    JSUint8Array bytes,
    int done,
    int total,
    String error,
    bool format,
    int id,
    JSInt32Array samples,
    int cacheBytes,
  });

  /// The message type.
  external String? get type;

  /// The protocol version (ready).
  external int? get version;

  /// The SF3 (decompress), the SoundFont (open) or the SF2 (result).
  external JSUint8Array? get bytes;

  /// The samples done (progress).
  external int? get done;

  /// The samples (progress).
  external int? get total;

  /// What failed (error).
  external String? get error;

  /// True when the file is not a valid SF3 (error).
  external bool? get format;

  /// The request of a sampler (samples, its result or error).
  external int? get id;

  /// The samples asked (samples).
  external JSInt32Array? get samples;

  /// The frames kept decoded at most, in bytes (open).
  external int? get cacheBytes;
}

/// The `buffer` of a JS typed array, for the transfer list of
/// `postMessage`.
extension MidiSoundFontJSTypedArrayBuffer on JSTypedArray {
  /// The ArrayBuffer of this view.
  external JSArrayBuffer get buffer;
}
