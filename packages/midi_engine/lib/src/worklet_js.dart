/// The AudioWorklet module: the names shared by the worklet and the player,
/// and the JS around the compiled Dart worklet.
library;

/// The name of the AudioWorklet processor.
const midiWorkletProcessorName = 'milomedy-midi-engine';

/// The global function the Dart worklet defines, which the processor calls
/// to create its engine host.
const midiWorkletFactoryName = 'milomedyMidiEngineWorklet';

/// The default file name of the worklet module, next to the page.
const midiWorkletDefaultUrl = 'midi_worklet.js';

/// The worklet module: [dart2js], the worklet main compiled with dart2js,
/// with what it needs around it in an AudioWorkletGlobalScope.
///
/// - `self`, which dart2js expects and a worklet does not have;
/// - the processor class, which only JS can declare (it extends
///   AudioWorkletProcessor): it calls the Dart host for each block of 128
///   frames.
String midiWorkletModule(String dart2js, {required String version}) =>
    '''
// AudioWorklet module of milomedy_midi_engine $version, built by
// `dart run milomedy_midi_engine:setup_web_worklet`. Do not edit.
var self = globalThis;
$dart2js
class MilomedyMidiEngineProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.dart = globalThis.$midiWorkletFactoryName(
      this.port,
      options.processorOptions,
      sampleRate,
    );
  }
  process(inputs, outputs, parameters) {
    var output = outputs[0];
    this.dart.process(output[0], output[1] || output[0], currentTime);
    return true;
  }
}
registerProcessor('$midiWorkletProcessorName', MilomedyMidiEngineProcessor);
''';
