/// MIDI engine, pure Dart: the timeline, the engine that plays it on the
/// audio clock, the mixer, the player and its outputs (silent, on a raw
/// audio stream), the engine host and its messages, offline rendering, WAV
/// files, a metronome, and the song of a MIDI file with its tempo map.
///
/// On the web: the Web Audio output is in `web_audio.dart`, the AudioWorklet
/// player in `web_worklet.dart`; `setup.dart` (dart:io) builds its worklet.
library;

export 'src/engine.dart';
export 'src/host.dart';
export 'src/metronome.dart';
export 'src/mixer.dart';
export 'src/offline.dart';
export 'src/player.dart';
export 'src/protocol.dart';
export 'src/sink.dart';
export 'src/song.dart';
export 'src/stream_sink.dart';
export 'src/synth_spec.dart';
export 'src/tempo_map.dart';
export 'src/timeline.dart';
export 'src/transport.dart';
export 'src/wav.dart';
