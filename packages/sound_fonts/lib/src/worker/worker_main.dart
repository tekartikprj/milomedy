/// The main of the SoundFont worker script (web only), built by
/// `setupMidiSoundFontWorker` (`dart run
/// milomedy_sound_fonts:setup_sound_font_worker`): turns the SF3 the page
/// sends into its SF2, out of the page's thread and heap.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:milomedy_vorbis/vorbis.dart';
import 'package:web/web.dart' as web;

// The decoder only, not the library (its storage, http).
import '../sf3.dart';
import 'js_message.dart';
import 'protocol.dart';

/// The worker script main.
void main() => midiSoundFontWorkerMain();

/// Decompresses the SF3 the page sends.
void midiSoundFontWorkerMain() {
  var scope = globalContext as web.DedicatedWorkerGlobalScope;
  scope.onmessage = (web.MessageEvent event) {
    var message = event.data as MidiSoundFontWorkerJsMessage?;
    if (message?.type == midiSoundFontWorkerMessageDecompress) {
      unawaited(_decompress(scope, message!.bytes!.toDart));
    }
  }.toJS;
  scope.postMessage(
    MidiSoundFontWorkerJsMessage(
      type: midiSoundFontWorkerMessageReady,
      version: midiSoundFontWorkerProtocolVersion,
    ),
  );
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
    var result = sf2.toJS;
    scope.postMessage(
      MidiSoundFontWorkerJsMessage(
        type: midiSoundFontWorkerMessageResult,
        bytes: result,
      ),
      [result.buffer].toJS,
    );
  } catch (e) {
    scope.postMessage(
      MidiSoundFontWorkerJsMessage(
        type: midiSoundFontWorkerMessageError,
        error: '$e',
        format: e is FormatException || e is VorbisDecoderException,
      ),
    );
  }
}
