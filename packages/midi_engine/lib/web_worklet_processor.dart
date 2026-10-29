/// The Dart side of the AudioWorklet processor: the main compiled with
/// dart2js by `setup_web_worklet`. It runs in the AudioWorkletGlobalScope (the
/// audio thread): an engine host per processor, driven by the messages of
/// its port, rendering each block of 128 frames into the output arrays.
///
/// dart2js only (dart2wasm would copy the output arrays); the page itself can
/// be compiled to wasm.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'midi_engine.dart';
import 'src/worklet_js.dart';

/// The typed data the worklet works with. dart2js only registers the native
/// classes the program creates: the typed arrays received from the page
/// would not be recognized otherwise.
final _typedData = <Object>[];

/// Defines the factory the processor class calls.
void midiWorkletMain() {
  _typedData.addAll([
    Float32List(0),
    Float64List(0),
    Int32List(0),
    Uint8List(0),
  ]);
  globalContext[midiWorkletFactoryName] = _create.toJS;
}

JSObject _create(web.MessagePort port, JSAny? options, JSNumber sampleRate) {
  var map = (options.dartify() as Map?) ?? const {};
  var host = MidiEngineHost(
    sampleRate: sampleRate.toDartDouble.round(),
    synths: [
      for (var spec in (map['synths'] as List?) ?? const [])
        MidiSynthSpec.fromMap(spec as Map),
    ],
    send: (event) => port.postMessage(event.jsify()),
  );
  port.onmessage = (web.MessageEvent event) {
    host.handle((event.data.dartify() as Map?) ?? const {});
  }.toJS;
  var failed = false;
  var processor = JSObject();
  processor['process'] =
      (JSFloat32Array left, JSFloat32Array right, JSNumber time) {
        var leftList = left.toDart;
        var rightList = right.toDart;
        try {
          host.render(leftList, rightList, time.toDartDouble);
        } catch (e) {
          leftList.fillRange(0, leftList.length, 0);
          rightList.fillRange(0, rightList.length, 0);
          if (!failed) {
            failed = true;
            port.postMessage(
              {'type': MidiHostEvents.error, 'message': '$e'}.jsify(),
            );
          }
        }
      }.toJS;
  return processor;
}
