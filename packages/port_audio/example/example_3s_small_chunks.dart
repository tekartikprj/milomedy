import 'dart:io';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_port_audio/port_audio.dart';
import 'package:wav/wav_file.dart';

import 'example_sound.dart';

Future<void> main(List<String> args) async {
  await streamFile(await exampleWavPath(seconds: 3));
}

Future<void> streamFile(String path) async {
  debugPortAudio = true;
  var portAudioLib = await getPortAudioLib();
  var err = await portAudioLib.initialize();
  if (err != paErrorCodeNoError) {
    stderr.writeln('PortAudio.initialize err: $err');
    exit(1);
  }
  PortAudioOutputStream? stream;
  var done = false;
  try {
    () async {
      while (!done) {
        await sleep(50);
        stdout.write('#');
        await stdout.flush();
      }
    }().unawait();

    var wav = await Wav.readFile(path);
    // ignore: avoid_print
    print(
      'Wav.channels: ${wav.format} ${wav.channels.length} ${wav.format} ${wav.samplesPerSecond}',
    );
    var sampleRate = wav.samplesPerSecond;

    var channels = wav.channels;
    var numChannels = channels.length;

    var frameCount = 5000;
    stream = portAudioLib.defaultOutputStream;
    err = await stream.open(
      parameters: PortAudioOutputStreamParameters(
        numChannels: numChannels,
        sampleRate: sampleRate.toDouble(),
        framesPerBuffer: frameCount,
      ),
    );

    () async {
      while (!done) {
        await sleep(50);
        stdout.write('#');
        await stdout.flush();
      }
    }().unawait();

    var streamInfo = await stream.getInfo();
    stdout.writeln('PortAudio.getStreamInfo: $streamInfo');
    var length = channels.first.length;
    for (var k = 0; k < 3; k++) {
      var time = await stream.getTime();
      stdout.writeln('PortAudio.getTime: $time');
      err = await stream.start();
      var i = 0;
      final buffer = List<double>.filled(frameCount, 0);
      while (true) {
        var j = 0;
        while (i < length && j < frameCount) {
          for (var channel = 0; channel < numChannels; channel++) {
            buffer[j++] = channels[channel][i];
          }
          i++;
        }
        if (j > 0) {
          var available = await stream.getWriteAvailable();
          stdout.writeln(
            'PortAudio.getWriteAvailable: $available (sending $j)',
          );
          await stream.writeDoubles(buffer.sublist(0, j));
        }

        if (i >= length) {
          break;
        }
      }
      err = await stream.stop();
      stdout.writeln('- Next song');

      await sleep(500);
    }
  } finally {
    done = true;
    await stream?.stop();
    await stream?.close();
    await portAudioLib.terminate();
  }

  /*
    stream = calloc<Pointer<PaStream>>();

    err = portAudioNativeLib.openDefaultStream(stream, 0, numChannels,
        paFormatFloat32, sampleRate.toDouble(), frameCount, nullptr, nullptr);
    print('PortAudio.openDefaultStream err: $err');

    err = portAudioNativeLib.startStream(stream.value);
    print('PortAudio.startStream err: $err');



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
          err = portAudioNativeLib.writeStream(
              stream.value, buffer.cast<Void>(), j);
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

   */
}
