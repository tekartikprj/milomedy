/// The AudioWorklet processor, in Dart: the main compiled with dart2js by
/// `setup_web_worklet`, whose output is the worklet module as it is. It runs
/// in the AudioWorkletGlobalScope (the audio thread): an engine host per
/// processor, driven by the messages of its port, rendering each block of
/// 128 frames into the output arrays.
///
/// Only JS can declare a class extending AudioWorkletProcessor, but
/// registerProcessor only needs a constructor whose prototype has `process`:
/// a Dart function is one, building the processor with Reflect.construct.
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

@JS('Reflect.construct')
external JSObject _construct(
  JSFunction target,
  JSArray<JSAny?> arguments,
  JSFunction newTarget,
);

@JS('Object.setPrototypeOf')
external void _setPrototypeOf(JSObject object, JSObject prototype);

@JS('registerProcessor')
external void _registerProcessor(String name, JSFunction constructor);

@JS('AudioWorkletProcessor')
external JSFunction get _audioWorkletProcessor;

/// The sample rate of the context, a global of the AudioWorkletGlobalScope.
@JS('sampleRate')
external double get _sampleRate;

/// The context time of the block rendered, a global of the
/// AudioWorkletGlobalScope.
@JS('currentTime')
external double get _currentTime;

/// The engine host of a processor.
class _Processor {
  final web.MessagePort port;
  final MidiEngineHost host;
  var failed = false;

  _Processor(this.port, this.host);

  void process(Float32List left, Float32List right) {
    try {
      host.render(left, right, _currentTime);
    } catch (e) {
      left.fillRange(0, left.length, 0);
      right.fillRange(0, right.length, 0);
      if (!failed) {
        failed = true;
        port.postMessage(
          {'type': MidiHostEvents.error, 'message': '$e'}.jsify(),
        );
      }
    }
  }
}

/// The processors, by the id stored on their JS object.
final _processors = <int, _Processor>{};

/// Registers the processor.
void midiWorkletMain() {
  // dart2js only registers the native typed data classes the program
  // creates: the typed arrays received from the page would not be
  // recognized otherwise.
  _keepTypedData([Float32List(0), Float64List(0), Int32List(0), Uint8List(0)]);
  late JSFunction constructor;
  constructor = (JSObject? options) {
    var processor = _construct(
      _audioWorkletProcessor,
      [options].toJS,
      constructor,
    );
    var port = processor['port'] as web.MessagePort;
    var map = (options?['processorOptions'].dartify() as Map?) ?? const {};
    var host = MidiEngineHost(
      sampleRate: _sampleRate.round(),
      synths: [
        for (var spec in (map['synths'] as List?) ?? const [])
          MidiSynthSpec.fromMap(spec as Map),
      ],
      send: (event) => port.postMessage(event.jsify()),
    );
    port.onmessage = (web.MessageEvent event) {
      host.handle((event.data.dartify() as Map?) ?? const {});
    }.toJS;
    var id = _processors.length;
    _processors[id] = _Processor(port, host);
    processor['dartId'] = id.toJS;
    return processor;
  }.toJS;
  var prototype = constructor['prototype'] as JSObject;
  _setPrototypeOf(prototype, _audioWorkletProcessor['prototype'] as JSObject);
  _setPrototypeOf(constructor, _audioWorkletProcessor);
  prototype['process'] =
      (
            JSObject processor,
            JSArray<JSArray<JSFloat32Array>> inputs,
            JSArray<JSArray<JSFloat32Array>> outputs,
            JSAny? parameters,
          ) {
            var output = outputs.toDart.first.toDart;
            var left = output.first.toDart;
            var right = output.length > 1 ? output[1].toDart : left;
            var id = (processor['dartId'] as JSNumber).toDartInt;
            _processors[id]!.process(left, right);
            // Keep the processor alive.
            return true.toJS;
          }
          .toJSCaptureThis;
  _registerProcessor(midiWorkletProcessorName, constructor);
}

/// Keeps [typedData] alive, so that dart2js keeps their classes.
final _typedData = <Object>[];

void _keepTypedData(List<Object> typedData) => _typedData.addAll(typedData);
