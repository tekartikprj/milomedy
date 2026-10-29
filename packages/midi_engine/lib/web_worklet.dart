/// The AudioWorklet player: the engine runs in an AudioWorklet, on the audio
/// thread, and this is its page side. The worklet module is built from Dart
/// by `dart run milomedy_midi_engine:setup_web_worklet`, next to the page.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'midi_engine.dart';
import 'src/worklet_js.dart';

export 'src/worklet_js.dart'
    show midiWorkletDefaultUrl, midiWorkletProcessorName;

/// A player whose engine runs in an AudioWorklet: nothing is rendered ahead,
/// so a command is heard after the output latency only, and a busy page
/// never makes a gap.
class MidiWorkletPlayer extends MidiHostPlayer {
  /// The audio context.
  final web.BaseAudioContext context;

  /// The worklet node.
  final web.AudioWorkletNode node;

  final bool _ownsContext;

  MidiWorkletPlayer._(
    this.context,
    this.node,
    int trackCount,
    this._ownsContext,
  ) : super(trackCount: trackCount) {
    node.port.onmessage = (web.MessageEvent event) {
      var data = event.data.dartify();
      if (data is Map) {
        handleEvent(data);
      }
    }.toJS;
  }

  /// A player of one track per synth of [synths], on [context] (a new
  /// AudioContext by default), its worklet module at [url], connected to
  /// [destination] (the context's by default).
  static Future<MidiWorkletPlayer> create({
    required List<MidiSynthSpec> synths,
    web.BaseAudioContext? context,
    String url = midiWorkletDefaultUrl,
    web.AudioNode? destination,
  }) async {
    var ownsContext = context == null;
    context ??= web.AudioContext();
    await context.audioWorklet.addModule(url).toDart;
    var processorOptions = JSObject()
      ..['synths'] = [for (var spec in synths) spec.toMap()].jsify();
    var node = web.AudioWorkletNode(
      context,
      midiWorkletProcessorName,
      web.AudioWorkletNodeOptions(
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2.toJS].toJS,
        processorOptions: processorOptions,
      ),
    );
    node.connect(destination ?? context.destination);
    return MidiWorkletPlayer._(context, node, synths.length, ownsContext);
  }

  @override
  void sendCommand(Map<String, Object?> command) =>
      node.port.postMessage(command.jsify());

  /// The context time heard now: the worklet reports the context time of the
  /// blocks it renders, heard after the output latency.
  @override
  double get clock {
    var context = this.context;
    if (context.isA<web.AudioContext>()) {
      var audioContext = context as web.AudioContext;
      return context.currentTime -
          audioContext.baseLatency -
          audioContext.outputLatency;
    }
    return context.currentTime;
  }

  @override
  Future<void> resumeOutput() async {
    var context = this.context;
    if (context.isA<web.AudioContext>() && context.state != 'running') {
      await (context as web.AudioContext).resume().toDart;
    }
  }

  @override
  Future<void> close() async {
    node.port.onmessage = null;
    node.port.close();
    node.disconnect();
    if (_ownsContext && context.isA<web.AudioContext>()) {
      await (context as web.AudioContext).close().toDart;
    }
    await super.close();
  }
}
