/// The AudioWorklet module: the names shared by the worklet and the player,
/// and the header of the module.
library;

/// The name of the AudioWorklet processor.
const midiWorkletProcessorName = 'milomedy-midi-engine';

/// The default file name of the worklet module, next to the page.
const midiWorkletDefaultUrl = 'midi_worklet.js';

/// The worklet module: [dart2js], the worklet main compiled with dart2js, as
/// it is (the processor registers itself from Dart), after a comment telling
/// where it comes from.
String midiWorkletModule(String dart2js, {required String version}) =>
    '''
// AudioWorklet module of milomedy_midi_engine $version, built by
// `dart run milomedy_midi_engine:setup_web_worklet`. Do not edit.
$dart2js''';
