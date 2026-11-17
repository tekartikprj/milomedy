import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../sf3.dart';
import 'decompressor.dart';
import 'js_message.dart';
import 'protocol.dart';

const _setupCommand = 'dart run milomedy_sound_fonts:setup_sound_font_worker';

/// On the web: a worker for each SF3.
MidiSoundFontDecompressor newMidiSoundFontDecompressor({
  required String url,
  required bool fallback,
  required Duration startTimeout,
}) =>
    (bytes, {onProgress}) => _decompress(
      bytes,
      url: url,
      fallback: fallback,
      startTimeout: startTimeout,
      onProgress: onProgress,
    );

Future<Uint8List> _decompress(
  Uint8List bytes, {
  required String url,
  required bool fallback,
  required Duration startTimeout,
  void Function(int done, int total)? onProgress,
}) async {
  if (!midiSoundFontIsCompressed(bytes)) {
    return bytes;
  }
  Future<Uint8List> inPage(String why) {
    if (!fallback) {
      throw MidiSoundFontWorkerException('$why ($_setupCommand builds it)');
    }
    web.console.warn(
      'MidiSoundFont: $why ($_setupCommand builds it), decompressing in the '
              'page'
          .toJS,
    );
    return midiSoundFontDecompress(bytes, onProgress: onProgress);
  }

  web.Worker worker;
  try {
    worker = web.Worker(url.toJS);
  } catch (e) {
    // A url the page refuses (content security policy).
    return inPage('cannot start $url ($e)');
  }
  var started = Completer<String?>();
  var result = Completer<Uint8List>();
  worker.onmessage = (web.MessageEvent event) {
    var message = event.data as MidiSoundFontWorkerJsMessage?;
    switch (message?.type) {
      case midiSoundFontWorkerMessageReady:
        var version = message!.version;
        if (!started.isCompleted) {
          started.complete(
            version == midiSoundFontWorkerProtocolVersion
                ? null
                : '$url speaks version $version, not '
                      '$midiSoundFontWorkerProtocolVersion',
          );
        }
      case midiSoundFontWorkerMessageProgress:
        onProgress?.call(message!.done!, message.total!);
      case midiSoundFontWorkerMessageResult:
        if (!result.isCompleted) {
          result.complete(message!.bytes!.toDart);
        }
      case midiSoundFontWorkerMessageError:
        if (!result.isCompleted) {
          var error = message!.error ?? 'error';
          result.completeError(
            message.format ?? false
                ? FormatException(error)
                : MidiSoundFontWorkerException(error),
          );
        }
    }
  }.toJS;
  worker.onerror = (web.Event event) {
    var error = event.isA<web.ErrorEvent>()
        ? (event as web.ErrorEvent).message
        : 'worker error';
    if (!started.isCompleted) {
      // Missing (404), not a script (an html page served instead)...
      started.complete('cannot load $url ($error)');
    } else if (!result.isCompleted) {
      // Gone while decompressing (out of memory?).
      result.completeError(MidiSoundFontWorkerException('$url: $error'));
    }
  }.toJS;
  try {
    var problem = await started.future.timeout(
      startTimeout,
      onTimeout: () => '$url did not start within $startTimeout',
    );
    if (problem != null) {
      return await inPage(problem);
    }
    // A copy, moved: the caller keeps its bytes.
    var sf3 = Uint8List.fromList(bytes).toJS;
    worker.postMessage(
      MidiSoundFontWorkerJsMessage(
        type: midiSoundFontWorkerMessageDecompress,
        bytes: sf3,
      ),
      [sf3.buffer].toJS,
    );
    return await result.future;
  } finally {
    worker.terminate();
  }
}
