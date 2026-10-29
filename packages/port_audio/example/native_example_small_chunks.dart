// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_port_audio/src/port_audio_native_lib.dart';
import 'package:wav/wav.dart';

import 'example_sound.dart';

Future<void> main(List<String> args) async {
  var portAudioNativeLib = await getPortAudioNativeLib();
  debugPortAudio = true;
  var err = portAudioNativeLib.initialize();
  Pointer<Pointer<PaStream>>? stream;
  try {
    print('PortAudio.initialize err: $err');

    var wav = await Wav.readFile(await exampleWavPath(seconds: 3));
    print(
      'Wav.channels: ${wav.format} ${wav.channels.length} ${wav.format} ${wav.samplesPerSecond}',
    );
    var sampleRate = wav.samplesPerSecond;

    var channels = wav.channels;
    var numChannels = channels.length;
    stream = calloc<Pointer<PaStream>>();
    var frameCount = 5000;
    err = portAudioNativeLib.openDefaultStream(
      stream,
      0,
      numChannels,
      paFormatFloat32,
      sampleRate.toDouble(),
      frameCount,
      nullptr,
      nullptr,
    );
    print('PortAudio.openDefaultStream err: $err');

    err = portAudioNativeLib.startStream(stream.value);
    print('PortAudio.startStream err: $err');

    var done = false;
    () async {
      while (!done) {
        await sleep(50);
        stdout.write('#');
        await stdout.flush();
      }
    }().unawait();

    var length = channels.first.length;
    for (var k = 0; k < 3; k++) {
      var i = 0;
      final buffer = calloc<Float>(frameCount * 4); // sizeof float32
      while (true) {
        var j = 0;
        while (i < length && j < frameCount) {
          for (var channel = 0; channel < numChannels; channel++) {
            buffer[j++] = channels[channel][i];
          }
          i++;
        }
        if (j > 0) {
          var available = portAudioNativeLib.getStreamWriteAvailable(
            stream.value,
          );
          if (debugPortAudio) {
            print('PortAudio.getStreamWriteAvailable: $available');
          }
          err = portAudioNativeLib.writeStream(
            stream.value,
            buffer.cast<Void>(),
            j,
          );
          if (debugPortAudio) {
            paLog('PortAudio.writeStream $j err: $err');
          }
        }
        if (i >= length) {
          break;
        }
      }

      await sleep(1000);
    }

    err = portAudioNativeLib.isStreamActive(stream.value);
    print('PortAudio.isStreamActive err: $err');

    if (err == paErrorCodeActive) {
      err = portAudioNativeLib.stopStream(stream.value);
      print('PortAudio.stopStream err: $err');
    }
    done = true;
  } finally {
    if (stream != null) {
      err = portAudioNativeLib.isStreamActive(stream.value);
      print('PortAudio.isStreamActive err: $err');

      if (err == paErrorCodeActive) {
        // This fails if not active
        err = portAudioNativeLib.abortStream(stream.value);
        print('PortAudio.abortStream err: $err');
      }

      err = portAudioNativeLib.closeStream(stream.value);
      print('PortAudio.closeStream err: $err');
      calloc.free(stream);
    }
    err = portAudioNativeLib.terminate();
    print('PortAudio.terminate err: $err');
  }
}
