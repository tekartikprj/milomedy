// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_port_audio/src/isolate.dart';
import 'package:tekartik_port_audio/src/port_audio_native_lib.dart';
import 'package:wav/wav.dart';

import 'example_sound.dart';

Future<void> main(List<String> args) async {
  // debugPortAudio = true;
  int? streamId;

  final receivePort = ReceivePort();
  await Isolate.spawn(workerIsolate, receivePort.sendPort);

  final sendPort = await receivePort.first as SendPort;
  var sender = MessageSender(sendPort: sendPort);
  // var err = portAudioNativeLib.initialize();
  //Pointer<Pointer<PaStream>>? stream;
  try {
    // print('PortAudio.initialize err: $err');

    var wav = await Wav.readFile(await exampleWavPath(seconds: 3));
    print(
      'Wav.channels: ${wav.format} ${wav.channels.length} ${wav.format} ${wav.samplesPerSecond}',
    );
    var sampleRate = wav.samplesPerSecond;

    var channels = wav.channels;
    var numChannels = channels.length;

    var frameCount = 512;

    var response = await sender.sendCommand(
      commandInitialize,
      CommandInitializeQuery(debug: debugPortAudio),
    );
    if (!response.success) {
      print('PortAudio.initialize error: ${response.error}');
      exit(1);
    }

    response = await sender.sendCommand(
      commandOpenDefaultStream,
      CommandOpenStreamQuery(
        numChannels: numChannels,
        sampleRate: sampleRate.toDouble(),
        framesPerBuffer: frameCount,
      ),
    );

    if (response.success) {
      streamId = CommandOpenStreamResult.fromList(response.result).streamId;
      print('streamId: $streamId');
    } else {
      throw StateError(response.toString());
    }

    response = await sender.sendCommand(
      commandStartStream,
      CommandStreamIdQuery(streamId: streamId),
    );

    if (!response.success) {
      throw StateError(response.toString());
    }
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
          response = await sender.sendCommand(
            commandWriteStream,
            CommandWriteStreamQuery(
              streamId: streamId,
              data: buffer.sublist(0, j),
            ),
          );

          if (!response.success) {
            //throw response;
          }

          //await sleep(10);
        }
        if (i >= length) {
          break;
        }
      }

      await sleep(500);
    }

    response = await sender.sendCommand(
      commandIsStreamActive,
      CommandStreamIdQuery(streamId: streamId),
    );

    if (!response.success && response.error == paErrorCodeActive) {
      response = await sender.sendCommand(
        commandStopStream,
        CommandStreamIdQuery(streamId: streamId),
      );
    }
    done = true;
  } finally {
    if (streamId != null) {
      var response = await sender.sendCommand(
        commandIsStreamActive,
        CommandStreamIdQuery(streamId: streamId),
      );

      if (!response.success && response.error == paErrorCodeActive) {
        response = await sender.sendCommand(
          commandAbortStream,
          CommandStreamIdQuery(streamId: streamId),
        );
      }

      response = await sender.sendCommand(
        commandCloseStream,
        CommandStreamIdQuery(streamId: streamId),
      );
    }

    var response = await sender.sendCommand(commandTerminate);

    print('PortAudio.terminate $response');
  }
}
