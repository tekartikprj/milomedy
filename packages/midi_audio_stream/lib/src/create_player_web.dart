import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';

/// The AudioWorklet player.
Future<MidiHostPlayer> midiCreatePlayerImpl({
  required List<MidiSynthSpec> synths,
  required String workletUrl,
  void Function()? isolateSetup,
}) => MidiWorkletPlayer.create(synths: synths, url: workletUrl);
