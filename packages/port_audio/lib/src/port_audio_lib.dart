import 'dart:isolate';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_port_audio/src/isolate.dart';
import 'package:tekartik_port_audio/src/port_audio_common.dart';
import 'package:tekartik_port_audio/src/port_audio_constant.dart';
import 'package:tekartik_port_audio/src/port_audio_native_lib.dart' as native;

/// PortAudio error
typedef PaError = int;

/// PortAudio stream
abstract class PortAudioOutputStream {
  /// Open the stream
  Future<int> open({required PortAudioOutputStreamParameters parameters});

  /// Start the stream
  Future<int> start();

  /// Stop the stream
  Future<int> stop();

  /// Close the stream
  Future<int> close();

  /// Write doubles
  Future<int> writeDoubles(List<double> buffer);

  /// Get the stream info
  Future<PaStreamInfo> getInfo();

  /// Get the stream time (seconds)
  Future<double> getTime();

  /// Get the write frame account available without blocking
  Future<int> getWriteAvailable();
}

abstract class _PortAudioOutputStream implements PortAudioOutputStream {}

class _PortAudioDefaultOutputStream implements _PortAudioOutputStream {
  final _PortAudioLib portAudioLib;

  Future<MessageSender> get _sender => portAudioLib._sender;
  int? streamId;
  final _lock = Lock();

  _PortAudioDefaultOutputStream({required this.portAudioLib});

  @override
  Future<int> open({
    required PortAudioOutputStreamParameters parameters,
  }) async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        return paErrorCodeStreamAlreadyOpened;
      }

      var numChannels = parameters.numChannels;
      var sampleRate = parameters.sampleRate;
      var framesPerBuffer = parameters.framesPerBuffer;
      var response = await sender.sendCommand(
        commandOpenDefaultStream,
        CommandOpenStreamQuery(
          numChannels: numChannels,
          sampleRate: sampleRate.toDouble(),
          framesPerBuffer: framesPerBuffer,
        ),
      );

      if (response.success) {
        streamId = CommandOpenStreamResult.fromList(response.result).streamId;
      }
      return response.error;
    });
  }

  @override
  Future<int> close() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandCloseStream,
          CommandStreamIdQuery(streamId: streamId!),
        );
        // The worker forgets the stream even on error, allow a new open.
        streamId = null;
        return response.error;
      } else {
        return paErrorCodeStreamNotOpened;
      }
    });
  }

  @override
  Future<int> start() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandStartStream,
          CommandStreamIdQuery(streamId: streamId!),
        );
        return response.error;
      } else {
        return paErrorCodeStreamNotOpened;
      }
    });
  }

  @override
  Future<int> writeDoubles(List<double> buffer) async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandWriteStream,
          CommandWriteStreamQuery(streamId: streamId!, data: buffer),
        );
        return response.error;
      } else {
        return paErrorCodeStreamNotOpened;
      }
    });
  }

  @override
  Future<int> stop() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandStopStream,
          CommandStreamIdQuery(streamId: streamId!),
        );
        return response.error;
      } else {
        return paErrorCodeStreamNotOpened;
      }
    });
  }

  /// Get the Stream time
  @override
  Future<double> getTime() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandGetStreamTime,
          CommandStreamIdQuery(streamId: streamId!),
        );
        if (response.success) {
          return (CommandDoubleResult.fromList(response.result)).value;
        }
      }
      return 0;
    });
  }

  /// Get the Stream write available
  @override
  Future<int> getWriteAvailable() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandGetStreamWriteAvailable,
          CommandStreamIdQuery(streamId: streamId!),
        );
        if (response.success) {
          return (CommandIntResult.fromList(response.result)).value;
        }
      }
      return 0;
    });
  }

  /// Get the device info
  @override
  Future<PaStreamInfo> getInfo() async {
    var sender = await _sender;
    return await _lock.synchronized(() async {
      if (streamId != null) {
        var response = await sender.sendCommand(
          commandGetStreamInfo,
          CommandStreamIdQuery(streamId: streamId!),
        );
        if (response.success) {
          var streamInfoResult = CommandGetStreamInfoResult.fromList(
            response.result,
          );
          return PaStreamInfo._(
            inputLatency: streamInfoResult.inputLatency,
            outputLatency: streamInfoResult.outputLatency,
            sampleRate: streamInfoResult.sampleRate,
          );
        }
      }
      throw StateError('Error getting stream info');
    });
  }
}

/// PortAudio output stream parameters
class PortAudioOutputStreamParameters {
  /// Number of channels
  final int numChannels;

  /// Sample rate
  final double sampleRate;

  /// Frames per buffer
  final int framesPerBuffer;

  /// Creates a [PortAudioOutputStreamParameters] instance with [numChannels], [sampleRate], and [framesPerBuffer].
  PortAudioOutputStreamParameters({
    required this.numChannels,
    required this.sampleRate,
    required this.framesPerBuffer,
  });
}

/// PortAudio library
abstract class PortAudioLib {
  /// Initialize the library
  Future<int> initialize();

  /// Terminate the library
  Future<int> terminate();

  /// Default stream
  PortAudioOutputStream get defaultOutputStream;

  /// Get the device count (< 0 means error)
  Future<int> getDeviceCount();

  /// Get the device count (< 0 means error)
  Future<int> getDefaultOutputDevice();

  /// Get the device info
  Future<PaDeviceInfo> getDeviceInfo(int index);
}

/// Device info
class PaDeviceInfo {
  /// Device name

  final String name;

  /// Maximum input channels
  final int maxInputChannels;

  /// Maximum output channels
  final int maxOutputChannels;

  /// Default low input latency (seconds)
  final double defaultLowInputLatency;

  /// Default low output latency (seconds)
  final double defaultLowOutputLatency;

  /// Default high input latency (seconds)
  final double defaultHighInputLatency;

  /// Default high output latency (seconds)
  final double defaultHighOutputLatency;

  /// Creates a [PaDeviceInfo] instance with device parameters.
  PaDeviceInfo._({
    required this.name,
    required this.maxInputChannels,
    required this.maxOutputChannels,
    required this.defaultLowInputLatency,
    required this.defaultLowOutputLatency,
    required this.defaultHighInputLatency,
    required this.defaultHighOutputLatency,
  });

  @override
  String toString() {
    return 'PaDeviceInfo(name: $name, maxInputChannels: $maxInputChannels, maxOutputChannels: $maxOutputChannels, defaultLowInputLatency: $defaultLowInputLatency, defaultLowOutputLatency: $defaultLowOutputLatency, defaultHighInputLatency: $defaultHighInputLatency, defaultHighOutputLatency: $defaultHighOutputLatency)';
  }
}

/// Device info
class PaStreamInfo {
  /// input latency (seconds)
  final double inputLatency;

  /// output latency (seconds)
  final double outputLatency;

  /// Sample rate
  final double sampleRate;

  /// Creates a [PaStreamInfo] instance with stream parameters.
  PaStreamInfo._({
    required this.inputLatency,
    required this.outputLatency,
    required this.sampleRate,
  });

  @override
  String toString() {
    return 'PaStreamInfo(inputLatency: $inputLatency, outputLatency: $outputLatency, sampleRate: $sampleRate)';
  }
}

/// Worker isolate entry: [args] is [SendPort, String? path].
Future<void> _workerIsolateEntry(List<Object?> args) =>
    workerIsolate(args[0] as SendPort, path: args[1] as String?);

class _PortAudioLib implements PortAudioLib {
  final native.PortAudioNativeLib portAudioNativeLib;

  /// Library path, also loaded by the worker isolate.
  final String? path;

  _PortAudioLib(this.portAudioNativeLib, {this.path});

  /// Default stream
  @override
  PortAudioOutputStream get defaultOutputStream =>
      _PortAudioDefaultOutputStream(portAudioLib: this);

  late final _sender = () async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_workerIsolateEntry, [receivePort.sendPort, path]);

    final sendPort = await receivePort.first as SendPort;
    var sender = MessageSender(sendPort: sendPort);
    return sender;
  }();

  @override
  Future<int> initialize() async {
    var sender = await _sender;
    var response = await sender.sendCommand(
      commandInitialize,
      CommandInitializeQuery(debug: debugPortAudio),
    );
    return response.error;
  }

  /// Get the device count
  @override
  Future<int> getDeviceCount() async {
    var sender = await _sender;
    var response = await sender.sendCommand(commandGetDeviceCount);
    if (response.success) {
      return (CommandIntResult.fromList(response.result)).value;
    }
    return response.error;
  }

  /// Get the device count
  @override
  Future<int> getDefaultOutputDevice() async {
    var sender = await _sender;
    var response = await sender.sendCommand(commandGetDefaultOutputDevice);
    if (response.success) {
      return (CommandIntResult.fromList(response.result)).value;
    }
    return response.error;
  }

  /// Get the device info
  @override
  Future<PaDeviceInfo> getDeviceInfo(int index) async {
    var sender = await _sender;
    var response = await sender.sendCommand(
      commandGetDeviceInfo,
      CommandIntQuery(value: index),
    );
    if (response.success) {
      var deviceInfoResult = CommandGetDeviceInfoResult.fromList(
        response.result,
      );
      return PaDeviceInfo._(
        name: deviceInfoResult.name,
        maxInputChannels: deviceInfoResult.maxInputChannels,
        maxOutputChannels: deviceInfoResult.maxOutputChannels,
        defaultLowInputLatency: deviceInfoResult.defaultLowInputLatency,
        defaultLowOutputLatency: deviceInfoResult.defaultLowOutputLatency,
        defaultHighInputLatency: deviceInfoResult.defaultHighInputLatency,
        defaultHighOutputLatency: deviceInfoResult.defaultHighOutputLatency,
      );
    } else {
      throw StateError('Error getting device info');
    }
  }

  @override
  Future<int> terminate() async {
    var sender = await _sender;
    var response = await sender.sendCommand(commandTerminate);
    return response.error;
  }
}

/// PortAudio library instance
_PortAudioLib? _portAudioLib;

/// Get the port audio library from a given path
/// subsequent calls will return the same instance
Future<PortAudioLib> getPortAudioLib({String? path}) async {
  _portAudioLib ??= _PortAudioLib(
    await native.getPortAudioNativeLib(path: path),
    path: path,
  );
  return _portAudioLib!;
}
