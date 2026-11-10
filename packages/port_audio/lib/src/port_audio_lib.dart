import 'dart:isolate';

import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_port_audio/src/isolate.dart';
import 'package:tekartik_port_audio/src/port_audio_common.dart';
import 'package:tekartik_port_audio/src/port_audio_constant.dart';
import 'package:tekartik_port_audio/src/port_audio_native_lib.dart' as native;

/// PortAudio error
typedef PaError = int;

/// A PortAudio output stream (float 32 samples, blocking writes): [open],
/// [start], [writeDoubles] again and again, [stop], [close].
abstract class PortAudioOutputStream {
  /// Opens the stream ([paErrorCodeStreamAlreadyOpened] when open).
  Future<int> open({required PortAudioOutputStreamParameters parameters});

  /// Starts the stream, before writing.
  Future<int> start();

  /// Stops the stream once the pending samples are played.
  Future<int> stop();

  /// Closes the stream (it can be opened again).
  Future<int> close();

  /// Writes [buffer]: samples from -1 to 1, interleaved when there are
  /// several channels (left, right, left...); completes once PortAudio took
  /// them. [paErrorCodeOutputUnderflowed] is harmless (a gap was played).
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

/// The PortAudio library, its calls run in a worker isolate (the blocking
/// writes never freeze the caller). Get it with [getPortAudioLib].
///
/// The calls return a PortAudio error code ([paErrorCodeNoError], 0, on
/// success) instead of throwing.
abstract class PortAudioLib {
  /// Initializes PortAudio, before any other call.
  Future<int> initialize();

  /// Terminates PortAudio and ends the worker isolate (the program cannot
  /// exit before): once, at the end. The library cannot be used again in
  /// the same process (the calls would never complete).
  Future<int> terminate();

  /// A new stream on the default output device, not opened: keep the
  /// reference, each access creates another one.
  PortAudioOutputStream get defaultOutputStream;

  /// The number of devices (< 0 means error).
  Future<int> getDeviceCount();

  /// The index of the default output device (< 0 means error or none).
  Future<int> getDefaultOutputDevice();

  /// The info of the device [index] (0 to [getDeviceCount] - 1); throws a
  /// [StateError] when there is no such device.
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

/// The PortAudio library of the process, loaded from [path] (the system
/// one by default: `libportaudio.so` on Linux, MacPorts'
/// `/opt/local/lib/libportaudio.dylib` on macOS, a dll downloaded to
/// `.local/lib/` on Windows); later calls return the same instance, the
/// first [path] wins.
Future<PortAudioLib> getPortAudioLib({String? path}) async {
  _portAudioLib ??= _PortAudioLib(
    await native.getPortAudioNativeLib(path: path),
    path: path,
  );
  return _portAudioLib!;
}
