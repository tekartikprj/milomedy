import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../definition.dart';
import '../sampler.dart';
import 'decompressor.dart';
import 'js_message.dart';
import 'protocol.dart';

const _setupCommand = 'dart run milomedy_sound_fonts:setup_sound_font_worker';

/// On the web: a worker for the session, holding the SoundFont.
Future<MidiSoundFontSampler> newMidiSoundFontSampler(
  Uint8List bytes, {
  required String url,
  required bool fallback,
  required Duration startTimeout,
  required int cacheBytes,
}) async {
  // Read here first: a bad file fails here, the page keeps the definition.
  var definition = MidiSoundFontDefinition.fromBytes(bytes);
  MidiSoundFontSampler inPage(String why) {
    if (!fallback) {
      throw MidiSoundFontWorkerException('$why ($_setupCommand builds it)');
    }
    web.console.warn(
      'MidiSoundFont: $why ($_setupCommand builds it), sampling in the page'
          .toJS,
    );
    return MidiSoundFontLocalSampler(bytes, cacheBytes: cacheBytes);
  }

  web.Worker worker;
  try {
    worker = web.Worker(url.toJS);
  } catch (e) {
    // A url the page refuses (content security policy).
    return inPage('cannot start $url ($e)');
  }
  var sampler = _WorkerSampler(worker, definition, url);
  var problem = await sampler._started.future.timeout(
    startTimeout,
    onTimeout: () => '$url did not start within $startTimeout',
  );
  if (problem != null) {
    worker.terminate();
    return inPage(problem);
  }
  // Moved: in the worker only. A view on part of a larger buffer is
  // copied first.
  if (bytes.offsetInBytes != 0 ||
      bytes.lengthInBytes != bytes.buffer.lengthInBytes) {
    bytes = Uint8List.fromList(bytes);
  }
  var soundFont = bytes.toJS;
  worker.postMessage(
    MidiSoundFontWorkerJsMessage(
      type: midiSoundFontWorkerMessageOpen,
      bytes: soundFont,
      cacheBytes: cacheBytes,
    ),
    [soundFont.buffer].toJS,
  );
  return sampler;
}

class _WorkerSampler extends MidiSoundFontSampler {
  final web.Worker _worker;
  final String _url;

  @override
  final MidiSoundFontDefinition definition;

  /// A problem (null when started).
  final _started = Completer<String?>();
  final _pending = <int, Completer<Uint8List>>{};
  var _nextId = 0;

  /// Why it cannot answer any more (the worker died, closed).
  Object? _dead;

  _WorkerSampler(this._worker, this.definition, this._url) {
    _worker.onmessage = (web.MessageEvent event) {
      var message = event.data as MidiSoundFontWorkerJsMessage?;
      switch (message?.type) {
        case midiSoundFontWorkerMessageReady:
          var version = message!.version;
          if (!_started.isCompleted) {
            _started.complete(
              version == midiSoundFontWorkerProtocolVersion
                  ? null
                  : '$_url speaks version $version, not '
                        '$midiSoundFontWorkerProtocolVersion',
            );
          }
        case midiSoundFontWorkerMessageResult:
          _pending.remove(message!.id)?.complete(message.bytes!.toDart);
        case midiSoundFontWorkerMessageError:
          var error = message!.error ?? 'error';
          _pending
              .remove(message.id)
              ?.completeError(
                message.format ?? false
                    ? FormatException(error)
                    : MidiSoundFontWorkerException(error),
              );
      }
    }.toJS;
    _worker.onerror = (web.Event event) {
      var error = event.isA<web.ErrorEvent>()
          ? (event as web.ErrorEvent).message
          : 'worker error';
      if (!_started.isCompleted) {
        // Missing (404), not a script (an html page served instead)...
        _started.complete('cannot load $_url ($error)');
        return;
      }
      // Gone (out of memory?): every request fails, and the next ones.
      _fail(MidiSoundFontWorkerException('$_url: $error'));
    }.toJS;
  }

  void _fail(Object error) {
    _dead ??= error;
    var pending = _pending.values.toList();
    _pending.clear();
    for (var completer in pending) {
      completer.completeError(error);
    }
  }

  @override
  Future<Uint8List> soundFont(Iterable<int> samples) {
    var dead = _dead;
    if (dead != null) {
      return Future.error(dead);
    }
    var id = _nextId++;
    var completer = _pending[id] = Completer<Uint8List>();
    _worker.postMessage(
      MidiSoundFontWorkerJsMessage(
        type: midiSoundFontWorkerMessageSamples,
        id: id,
        samples: Int32List.fromList(samples.toList()).toJS,
      ),
    );
    return completer.future;
  }

  @override
  Future<void> close() async {
    _worker.terminate();
    _fail(StateError('sampler closed'));
  }
}
