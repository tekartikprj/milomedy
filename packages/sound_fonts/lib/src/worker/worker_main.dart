/// The main of the SoundFont worker script (web only), built by
/// `setupMidiSoundFontWorker` (`dart run
/// milomedy_sound_fonts:setup_sound_font_worker`), out of the page's thread
/// and heap: turns the SF3 the page sends into its SF2, or keeps the
/// SoundFont of a sampler and makes the SoundFont of each song from it.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';
import 'package:web/web.dart' as web;

// The decoder only, not the library (its storage, http).
import '../sampler.dart';
import '../sf3.dart';
import 'js_message.dart';
import 'protocol.dart';

/// The worker script main.
void main() => midiSoundFontWorkerMain();

/// Answers the page.
void midiSoundFontWorkerMain() {
  var scope = globalContext as web.DedicatedWorkerGlobalScope;
  MidiSoundFontLocalSampler? sampler;
  Object? openError;
  scope.onmessage = (web.MessageEvent event) {
    var message = event.data as MidiSoundFontWorkerJsMessage?;
    switch (message?.type) {
      case midiSoundFontWorkerMessageDecompress:
        unawaited(_decompress(scope, message!.bytes!.toDart));
      case midiSoundFontWorkerMessageOpen:
        try {
          sampler = MidiSoundFontLocalSampler(
            message!.bytes!.toDart,
            cacheBytes: message.cacheBytes ?? midiSoundFontSamplerCacheBytes,
            // No page to keep responsive.
            slice: const Duration(seconds: 1),
          );
        } catch (e) {
          openError = e;
        }
      case midiSoundFontWorkerMessageSamples:
        unawaited(
          _samples(
            scope,
            message!.id!,
            sampler,
            openError,
            message.samples!.toDart,
          ),
        );
    }
  }.toJS;
  scope.postMessage(
    MidiSoundFontWorkerJsMessage(
      type: midiSoundFontWorkerMessageReady,
      version: midiSoundFontWorkerProtocolVersion,
    ),
  );
}

void _error(web.DedicatedWorkerGlobalScope scope, Object e, {int? id}) {
  var format = e is FormatException || e is VorbisDecoderException;
  scope.postMessage(
    id == null
        ? MidiSoundFontWorkerJsMessage(
            type: midiSoundFontWorkerMessageError,
            error: '$e',
            format: format,
          )
        : MidiSoundFontWorkerJsMessage(
            type: midiSoundFontWorkerMessageError,
            id: id,
            error: '$e',
            format: format,
          ),
  );
}

/// Sends [bytes] (in their own buffer: moved, not copied).
void _result(web.DedicatedWorkerGlobalScope scope, Uint8List bytes, {int? id}) {
  var result = bytes.toJS;
  scope.postMessage(
    id == null
        ? MidiSoundFontWorkerJsMessage(
            type: midiSoundFontWorkerMessageResult,
            bytes: result,
          )
        : MidiSoundFontWorkerJsMessage(
            type: midiSoundFontWorkerMessageResult,
            id: id,
            bytes: result,
          ),
    [result.buffer].toJS,
  );
}

Future<void> _samples(
  web.DedicatedWorkerGlobalScope scope,
  int id,
  MidiSoundFontLocalSampler? sampler,
  Object? openError,
  Int32List samples,
) async {
  if (openError != null) {
    _error(scope, openError, id: id);
    return;
  }
  try {
    if (sampler == null) {
      throw StateError('no SoundFont opened');
    }
    _result(scope, await sampler.soundFont(samples), id: id);
  } catch (e) {
    _error(scope, e, id: id);
  }
}

Future<void> _decompress(
  web.DedicatedWorkerGlobalScope scope,
  Uint8List bytes,
) async {
  try {
    var sf2 = await midiSoundFontDecompress(
      bytes,
      onProgress: (done, total) => scope.postMessage(
        MidiSoundFontWorkerJsMessage(
          type: midiSoundFontWorkerMessageProgress,
          done: done,
          total: total,
        ),
      ),
      // No page to keep responsive: the messages go out anyway.
      slice: const Duration(seconds: 1),
    );
    // In its own buffer (written in one): moved, not copied.
    _result(scope, sf2);
  } catch (e) {
    _error(scope, e);
  }
}
