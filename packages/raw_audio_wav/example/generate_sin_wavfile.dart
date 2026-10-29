import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekartik_raw_audio/generator.dart';
import 'package:tekartik_raw_audio_wav/raw_audio_wav.dart';

Future<void> main(List<String> args) async {
  var manager = RawAudioManagerWav();
  var output = manager.createOutput(
    options: RawAudioOutputOptions(sampleRate: 44100, channelCount: 1),
  );
  var sinWavData = pcm16GenerateExampleAudioData();
  await output.feed(sinWavData);
  var wav = output.wav;
  await writeBytes(File(join('.local', 'example.wav')), wav.write());
}
