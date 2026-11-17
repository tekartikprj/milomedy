/// Compresses a SoundFont to SF3 with ffmpeg (io only, for tools): each
/// sample encoded to Ogg Vorbis by `ffmpeg -c:a libvorbis`.
///
/// ```dart
/// var sf3 = await midiSoundFontCompress(
///   sf2,
///   encode: midiFfmpegVorbisEncoder(quality: 4),
/// );
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:process_run/shell.dart';

import 'src/sf3.dart';

export 'src/sf3.dart' show MidiSoundFontSampleEncoder, midiSoundFontCompress;

/// An encoder of samples to Ogg Vorbis by ffmpeg (found on the PATH) at
/// [quality] (`-q:a`, -1 to 10; 4 by default, about 128 kbit/s for a
/// stereo 44.1 kHz stream), one ffmpeg run per sample, its files in a
/// temporary folder.
///
/// libvorbis writes the length of each stream in its last granule
/// position: the decoder gives back the same number of frames.
MidiSoundFontSampleEncoder midiFfmpegVorbisEncoder({
  double quality = 4,
  String ffmpeg = 'ffmpeg',
}) {
  var shell = Shell(verbose: false);
  return (frames, sampleRate) async {
    var folder = await Directory.systemTemp.createTemp('milomedy_sf3_');
    try {
      var input = File(join(folder.path, 'sample.raw'));
      var output = File(join(folder.path, 'sample.ogg'));
      var data = ByteData(frames.length * 2);
      for (var i = 0; i < frames.length; i++) {
        data.setInt16(i * 2, frames[i], Endian.little);
      }
      await input.writeAsBytes(data.buffer.asUint8List());
      await shell.runExecutableArguments(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-y',
        '-f',
        's16le',
        '-ar',
        '$sampleRate',
        '-ac',
        '1',
        '-i',
        input.path,
        '-c:a',
        'libvorbis',
        '-q:a',
        '$quality',
        '-map_metadata',
        '-1',
        '-fflags',
        '+bitexact',
        '-f',
        'ogg',
        output.path,
      ]);
      return Uint8List.fromList(await output.readAsBytes());
    } finally {
      await folder.delete(recursive: true);
    }
  };
}
