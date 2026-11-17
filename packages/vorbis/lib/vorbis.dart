/// Ogg Vorbis decoding, pure Dart: [decodeOgg] gives the frames of a
/// stream in memory (interleaved float PCM), [decodeOggInt16] its 16-bit
/// frames written where given, [probeOgg] its format, [float32ToInt16]
/// 16-bit frames; [VorbisSetupCache] parses the setup shared by many
/// streams once.
///
/// vorbis_decoder 0.0.1-dev.1 (github.com/dotkebi/vorbis_decoder, MIT, a
/// port of NVorbis), vendored: see the README.
library;

export 'src/decoder.dart';
export 'src/vorbis/core.dart' show VorbisSetupCache, floatToInt16;
