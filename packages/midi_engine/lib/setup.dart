/// The setup of an app on the web (dart:io, run from a tool): builds the
/// AudioWorklet module of the engine from Dart.
library;

export 'src/setup/web_worklet_setup.dart'
    show MidiWebWorkletSetupResult, setupMidiWebWorklet;
export 'src/worklet_js.dart'
    show midiWorkletDefaultUrl, midiWorkletProcessorName;
