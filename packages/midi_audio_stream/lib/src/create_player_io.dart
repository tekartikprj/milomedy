import 'package:milomedy_midi_engine/isolate_player.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

import 'mp_audio_stream_output.dart';

/// The isolate player on mp_audio_stream.
Future<MidiHostPlayer> midiCreatePlayerImpl({
  required List<MidiSynthSpec> synths,
  required String workletUrl,
  void Function()? isolateSetup,
}) => MidiIsolatePlayer.spawn(
  synths: synths,
  openStream: midiMpAudioStreamOpener,
  setup: isolateSetup,
);
