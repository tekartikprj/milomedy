/// The MIDI engine on every platform: an isolate feeding mp_audio_stream on
/// Android, iOS, Linux, macOS and Windows, an AudioWorklet on the web.
library;

import 'package:milomedy_midi_engine/midi_engine.dart';

import 'src/create_player_io.dart'
    if (dart.library.js_interop) 'src/create_player_web.dart';

export 'src/mp_audio_stream_output.dart'
    if (dart.library.js_interop) 'src/mp_audio_stream_output_web.dart';

/// A player of one track per synth of [synths]: in a background isolate on
/// mp_audio_stream, or in an AudioWorklet on the web, its module at
/// [workletUrl] (built by `dart run milomedy_midi_engine:setup_web_worklet`).
///
/// On the web, call it after a user gesture.
Future<MidiHostPlayer> midiCreatePlayer({
  required List<MidiSynthSpec> synths,
  String workletUrl = 'midi_worklet.js',
}) => midiCreatePlayerImpl(synths: synths, workletUrl: workletUrl);
