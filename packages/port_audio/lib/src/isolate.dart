// ignore_for_file: public_member_api_docs

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'port_audio_native_lib.dart';

/// Pa_Initialize
const commandInitialize = 1;

/// Pa_OpenDefaultStream
const commandOpenDefaultStream = 2;

/// Pa_StartStream
const commandStartStream = 3;

/// Pa_WriteStream
const commandWriteStream = 4;

/// Pa_IsStreamActive
const commandIsStreamActive = 5;

/// Pa_StopStream
const commandStopStream = 6;

/// Pa_AbortStream
const commandAbortStream = 7;

/// Pa_CloseStream
const commandCloseStream = 8;

/// Pa_Terminate
const commandTerminate = 9;

/// Pa_GetDeviceCount
const commandGetDeviceCount = 10;

/// Pa_GetDefaultOutputDevice
const commandGetDefaultOutputDevice = 11;

/// Pa_GetDeviceInfo
const commandGetDeviceInfo = 12;

/// Pa_GetStreamInfo
const commandGetStreamInfo = 13;

/// Pa_GetStreamTime
const commandGetStreamTime = 14;

/// Pa_GetStreamWriteAvailable
const commandGetStreamWriteAvailable = 15;

/// Message response
class MessageResponse {
  /// true on success
  late final bool success;
  List<Object?>? _result;

  /// result
  List<Object?> get result => _result!;

  /// error
  PaErrorDart get error =>
      success ? paErrorCodeNoError : (result[0] as PaErrorDart);

  /// result as list
  List<Object?> toList() {
    return [success, if (_result != null) result];
  }

  /// success
  MessageResponse.success([List<Object?>? result])
    : success = true,
      _result = result;

  /// error
  MessageResponse.error(PaErrorDart err) : success = false, _result = [err];

  /// from list
  MessageResponse.fromList(List args) {
    success = args[0] as bool;
    if (args.length > 1) {
      _result = args[1] as List<Object?>?;
    }
  }

  @override
  String toString() {
    return 'MessageResponse(success: $success, result: ${toList().sublist(1)})';
  }
}

/// Message request
class MessageRequest {
  /// send port
  late final SendPort sendPort;

  /// command
  late final int command;
  List<Object?>? _query;

  /// query
  List<Object?> get query => _query!;

  /// Creates a [MessageRequest] with [sendPort], [command], and optional [_query].
  MessageRequest({required this.sendPort, required this.command, this._query});

  /// to list
  List<Object?> toList() {
    return [sendPort, command, if (_query != null) query];
  }

  /// from list
  MessageRequest.fromList(List args) {
    sendPort = args[0] as SendPort;
    command = args[1] as int;
    if (args.length > 2) {
      _query = args[2] as List<Object?>?;
    }
  }
}

/// CommandOpenStreamResult
class CommandOpenStreamResult implements MessageResult {
  /// stream id
  late final int streamId;
  @override
  List<Object?> toList() {
    return [streamId];
  }

  /// Creates a [CommandOpenStreamResult] with [streamId].
  CommandOpenStreamResult({required this.streamId});

  /// from list
  CommandOpenStreamResult.fromList(List args) {
    streamId = args[0] as int;
  }
}

/// CommandOpenStreamResult
typedef CommandIntResult = _CommandValueResult<int>;

typedef CommandDoubleResult = _CommandValueResult<double>;

class _CommandValueResult<T> implements MessageResult {
  /// stream id
  late final T value;
  @override
  List<Object?> toList() {
    return [value];
  }

  /// Creates a [_CommandValueResult] with [value].
  _CommandValueResult({required this.value});

  /// from list
  // ignore: unused_element
  _CommandValueResult.fromList(List args) {
    value = args[0] as T;
  }
}

abstract class _Message {
  List<Object?> toList();
}

/// MessageResult
abstract class MessageResult implements _Message {}

/// MessageQuery
abstract class MessageQuery implements _Message {}

/// CommandInitializeQuery
class CommandInitializeQuery implements MessageQuery {
  late final bool debug;
  @override
  List<Object?> toList() {
    return [debug];
  }

  /// Creates a [CommandInitializeQuery] with [debug] flag.
  CommandInitializeQuery({required this.debug});

  /// from list
  CommandInitializeQuery.fromList(List args) {
    debug = args[0] as bool;
  }
}

/// CommandIntQuery (get device info)
class CommandIntQuery implements MessageQuery {
  late final int value;
  @override
  List<Object?> toList() {
    return [value];
  }

  /// Creates a [CommandIntQuery] with [value].
  CommandIntQuery({required this.value});

  /// from list
  CommandIntQuery.fromList(List args) {
    value = args[0] as int;
  }
}

class CommandStreamIdQuery implements MessageQuery {
  late final int streamId;
  @override
  List<Object?> toList() {
    return [streamId];
  }

  CommandStreamIdQuery({required this.streamId});
  CommandStreamIdQuery.fromList(List args) {
    streamId = args[0] as int;
  }
}

class CommandWriteStreamQuery extends CommandStreamIdQuery {
  late final List<double> data;
  @override
  List<Object?> toList() {
    return [streamId, data];
  }

  CommandWriteStreamQuery({required super.streamId, required this.data});
  CommandWriteStreamQuery.fromList(List args) : super.fromList(args) {
    data = (args[1] as List).cast<double>();
  }
}

class CommandOpenStreamQuery implements MessageQuery {
  late final int numChannels;
  late final double sampleRate;
  late final int framesPerBuffer;

  @override
  List<Object?> toList() {
    return [numChannels, sampleRate, framesPerBuffer];
  }

  CommandOpenStreamQuery({
    required this.numChannels,
    required this.sampleRate,
    required this.framesPerBuffer,
  });
  CommandOpenStreamQuery.fromList(List args) {
    numChannels = args[0] as int;
    sampleRate = args[1] as double;
    framesPerBuffer = args[2] as int;
  }
}

class CommandGetDeviceInfoResult implements MessageResult {
  late final String name;
  late final int maxInputChannels;
  late final int maxOutputChannels;
  late final double defaultLowInputLatency;
  late final double defaultLowOutputLatency;
  late final double defaultHighInputLatency;
  late final double defaultHighOutputLatency;

  @override
  List<Object?> toList() {
    return [
      name,
      maxInputChannels,
      maxOutputChannels,
      defaultLowInputLatency,
      defaultLowOutputLatency,
      defaultHighInputLatency,
      defaultHighOutputLatency,
    ];
  }

  CommandGetDeviceInfoResult({
    required this.name,
    required this.maxInputChannels,
    required this.maxOutputChannels,
    required this.defaultLowInputLatency,
    required this.defaultLowOutputLatency,
    required this.defaultHighInputLatency,
    required this.defaultHighOutputLatency,
  });
  CommandGetDeviceInfoResult.fromList(List args) {
    name = args[0] as String;
    maxInputChannels = args[1] as int;
    maxOutputChannels = args[2] as int;
    defaultLowInputLatency = args[3] as double;
    defaultLowOutputLatency = args[4] as double;
    defaultHighInputLatency = args[5] as double;
    defaultHighOutputLatency = args[6] as double;
  }
}

class CommandGetStreamInfoResult implements MessageResult {
  late final double inputLatency;
  late final double outputLatency;
  late final double sampleRate;

  @override
  List<Object?> toList() {
    return [inputLatency, outputLatency, sampleRate];
  }

  CommandGetStreamInfoResult({
    required this.inputLatency,
    required this.outputLatency,
    required this.sampleRate,
  });
  CommandGetStreamInfoResult.fromList(List args) {
    inputLatency = args[0] as double;
    outputLatency = args[1] as double;
    sampleRate = args[2] as double;
  }
}

/// WorkerStreamInfo
class WorkerStreamInfo {
  late final int streamId;
  late final Pointer<PaStream> stream;
  late final int numChannels;
  late final int framesPerBuffer;
  late final Pointer<Float> buffer;
  WorkerStreamInfo({
    required this.streamId,
    required this.stream,
    required this.numChannels,
    required this.framesPerBuffer,
  }) {
    buffer = calloc<Float>(framesPerBuffer * 4);
  }
  void dispose() {
    calloc.free(buffer);
    //calloc.free(stream); // not needed
  }
}

/// Worker isolate entry point, [path] is the portaudio library path (default
/// one if null).
Future<void> workerIsolate(SendPort sendPort, {String? path}) async {
  var portAudioNativeLib = await getPortAudioNativeLib(path: path);
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  var streamId = 0;
  final openedStreams = <int, WorkerStreamInfo>{};
  final lock = Lock();
  var doneCompleter = Completer<void>();
  var subscription = receivePort.listen((message) async {
    await lock.synchronized(() async {
      if (message is List) {
        var messageArgs = MessageRequest.fromList(message);
        var responsePort = messageArgs.sendPort;
        var command = messageArgs.command;

        void sendSuccess([MessageResult? result]) {
          responsePort.send(MessageResponse.success(result?.toList()).toList());
        }

        void sendError(PaErrorDart err) {
          if (err == paErrorCodeNoError) {
            sendSuccess();
          } else {
            responsePort.send(MessageResponse.error(err).toList());
          }
        }

        switch (command) {
          case commandInitialize:
            var query = CommandInitializeQuery.fromList(messageArgs.query);
            debugPortAudio = query.debug;

            var err = portAudioNativeLib.initialize();
            if (debugPortAudio) {
              paLog('PortAudio.initialize err: $err');
            }
            sendError(err);
            break;
          case commandGetDeviceCount:
            var err = portAudioNativeLib.getDeviceCount();
            if (debugPortAudio) {
              paLog('PortAudio.getDeviceCount err/value: $err');
            }
            if (err >= 0) {
              sendSuccess(CommandIntResult(value: err));
            } else {
              sendError(err);
            }
            break;
          case commandGetDefaultOutputDevice:
            var err = portAudioNativeLib.getDefaultOutputDevice();
            if (debugPortAudio) {
              paLog('PortAudio.getDefaultOutputDevice err/value: $err');
            }
            if (err >= 0) {
              sendSuccess(CommandIntResult(value: err));
            } else {
              sendError(err);
            }
            break;

          case commandGetDeviceInfo:
            var query = CommandIntQuery.fromList(messageArgs.query);
            var index = query.value;

            var infoPtr = portAudioNativeLib.getDeviceInfo(index);

            var info = infoPtr.ref;
            var result = CommandGetDeviceInfoResult(
              name: info.name.toDartString(),
              maxInputChannels: info.maxInputChannels,
              maxOutputChannels: info.maxOutputChannels,
              defaultLowInputLatency: info.defaultLowInputLatency,
              defaultLowOutputLatency: info.defaultLowOutputLatency,
              defaultHighInputLatency: info.defaultHighInputLatency,
              defaultHighOutputLatency: info.defaultHighOutputLatency,
            );
            if (debugPortAudio) {
              paLog('PortAudio.getDeviceInfo: ${result.toList()}');
            }
            sendSuccess(result);
            break;
          case commandTerminate:
            var err = portAudioNativeLib.terminate();
            if (debugPortAudio) {
              paLog('PortAudio.terminate err: $err');
            }
            sendError(err);
            if (!doneCompleter.isCompleted) {
              doneCompleter.complete();
            }
            break;
          case commandOpenDefaultStream:
            var query = CommandOpenStreamQuery.fromList(messageArgs.query);
            var stream = calloc<Pointer<PaStream>>();
            var numChannels = query.numChannels;
            var sampleRate = query.sampleRate;
            var framesPerBuffer = query.framesPerBuffer;
            var err = portAudioNativeLib.openDefaultStream(
              stream,
              0,
              numChannels,
              paFormatFloat32,
              sampleRate,
              framesPerBuffer,
              nullptr,
              nullptr,
            );
            if (debugPortAudio) {
              paLog('PortAudio.openDefaultStream err: $err');
            }
            if (err == paErrorCodeNoError) {
              openedStreams[++streamId] = WorkerStreamInfo(
                streamId: streamId,
                stream: stream.value,
                numChannels: numChannels,
                framesPerBuffer: framesPerBuffer,
              );
              sendSuccess(CommandOpenStreamResult(streamId: streamId));
            } else {
              sendError(err);
            }
            break;
          case commandGetStreamTime:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var time = portAudioNativeLib.getStreamTime(stream);
              if (debugPortAudio) {
                paLog('PortAudio.getStreamTime time: $time');
              }
              sendSuccess(CommandDoubleResult(value: time));
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
          case commandGetStreamWriteAvailable:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var available = portAudioNativeLib.getStreamWriteAvailable(
                stream,
              );
              if (debugPortAudio) {
                paLog('PortAudio.getStreamWriteAvailable(): $available');
              }
              sendSuccess(CommandIntResult(value: available));
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
          case commandGetStreamInfo:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var infoPtr = portAudioNativeLib.getStreamInfo(stream);

              var info = infoPtr.ref;
              var result = CommandGetStreamInfoResult(
                inputLatency: info.inputLatency,
                outputLatency: info.outputLatency,
                sampleRate: info.sampleRate,
              );
              if (debugPortAudio) {
                paLog('PortAudio.getStreamInfo: ${result.toList()}');
              }
              sendSuccess(result);
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
          case commandStartStream:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var err = portAudioNativeLib.startStream(stream);
              if (debugPortAudio) {
                paLog('PortAudio.startStream err: $err');
              }
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }
            break;
          case commandWriteStream:
            var query = CommandWriteStreamQuery.fromList(messageArgs.query);
            var info = openedStreams[query.streamId];
            if (info != null) {
              // Interleaved samples, a frame has one sample per channel.
              var sampleCount = query.data.length;
              var frameCount = sampleCount ~/ info.numChannels;
              Pointer<Float> buffer;
              Pointer<Float>? allocatedBuffer;
              if (sampleCount > info.framesPerBuffer) {
                allocatedBuffer = calloc<Float>(sampleCount * 4);
                buffer = allocatedBuffer;
              } else {
                buffer = info.buffer;
              }

              for (var i = 0; i < sampleCount; i++) {
                buffer[i] = query.data[i];
              }
              var err = portAudioNativeLib.writeStream(
                info.stream,
                buffer.cast<Void>(),
                frameCount,
              );
              if (allocatedBuffer != null) {
                calloc.free(allocatedBuffer);
              }

              if (debugPortAudio) {
                paLog('PortAudio.writeStream $frameCount err: $err');
              }
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }
            break;
          case commandIsStreamActive:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var err = portAudioNativeLib.isStreamActive(stream);
              if (debugPortAudio) {
                paLog('PortAudio.isStreamActive err: $err');
              }
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }
            break;
          case commandStopStream:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var err = portAudioNativeLib.stopStream(stream);
              if (debugPortAudio) {
                paLog('PortAudio.stopStream err: $err');
              }
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
          case commandAbortStream:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var stream = openedStreams[query.streamId]?.stream;
            if (stream != null) {
              var err = portAudioNativeLib.abortStream(stream);
              if (debugPortAudio) {
                paLog('PortAudio.abortStream err: $err');
              }
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
          case commandCloseStream:
            var query = CommandStreamIdQuery.fromList(messageArgs.query);
            var info = openedStreams[query.streamId];
            if (info != null) {
              var err = portAudioNativeLib.closeStream(info.stream);
              if (debugPortAudio) {
                paLog('PortAudio.closeStream err: $err');
              }
              info.dispose();
              openedStreams.remove(query.streamId);
              sendError(err);
            } else {
              sendError(paErrorCodeInvalidStream);
            }

            break;
        }
      }
    });
  });
  await doneCompleter.future;
  await lock.synchronized(() async {
    await subscription.cancel();
    for (var info in openedStreams.values) {
      var err = portAudioNativeLib.abortStream(info.stream);
      if (debugPortAudio) {
        paLog('PortAudio.closeStream err: $err');
      }
      info.dispose();
    }
  });
  Isolate.current.kill();
}

class MessageSender {
  final SendPort sendPort;

  MessageSender({required this.sendPort});
  Future<MessageResponse> sendCommand(
    int command, [
    MessageQuery? query,
  ]) async {
    final responsePort = ReceivePort();
    sendPort.send([
      responsePort.sendPort,
      command,
      if (query != null) query.toList(),
    ]);
    return MessageResponse.fromList(await responsePort.first as List);
  }
}
