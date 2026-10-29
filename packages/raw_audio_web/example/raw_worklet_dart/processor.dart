/// The AudioWorklet module, in Dart: compiled with dart2js to processor.js
/// (`dart run tool/build_raw_worklet_dart.dart`), it runs on the audio
/// thread, in an AudioWorkletGlobalScope, and is called for each block of
/// 128 frames.
///
/// Only JS can declare a class extending AudioWorkletProcessor, but
/// registerProcessor only needs a constructor whose prototype has `process`:
/// a Dart function is one, building the processor with Reflect.construct.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

/// The state of a processor: the level of its input, posted to the page.
class _PassThrough {
  final web.MessagePort port;
  var blocks = 0;
  var sum = 0.0;
  var count = 0;

  _PassThrough(this.port);

  void process(List<Float32List> input, List<Float32List> output) {
    // Copy the input to the output, channel by channel (no input yet: the
    // output stays silent).
    if (input.isNotEmpty) {
      for (var channel = 0; channel < output.length; channel++) {
        output[channel].setAll(0, input[math.min(channel, input.length - 1)]);
      }
      for (var sample in input.first) {
        sum += sample * sample;
      }
      count += input.first.length;
    }
    // The level of the first channel, posted to the page about 20 times a
    // second.
    if (++blocks % 16 == 0) {
      var rms = count > 0 ? math.sqrt(sum / count) : 0.0;
      port.postMessage({'level': rms}.jsify());
      sum = 0;
      count = 0;
    }
  }
}

/// The processors, by the id stored on their JS object.
final _processors = <int, _PassThrough>{};

void main() {
  // dart2js only registers the typed data classes the program creates: the
  // Float32Arrays of the audio thread would not be recognized otherwise.
  Float32List(0);

  late JSFunction constructor;
  constructor = (JSAny? options) {
    var processor = _construct(
      _audioWorkletProcessor,
      [options].toJS,
      constructor,
    );
    var id = _processors.length;
    _processors[id] = _PassThrough(processor['port'] as web.MessagePort);
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
            var id = (processor['dartId'] as JSNumber).toDartInt;
            _processors[id]!.process(
              [for (var channel in inputs.toDart.first.toDart) channel.toDart],
              [for (var channel in outputs.toDart.first.toDart) channel.toDart],
            );
            // Keep the processor alive.
            return true.toJS;
          }
          .toJSCaptureThis;
  _registerProcessor('pass-through-dart', constructor);
}
