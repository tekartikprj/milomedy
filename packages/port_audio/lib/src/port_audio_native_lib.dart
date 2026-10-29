// ignore_for_file: public_member_api_docs

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_http_io/http_client_io.dart';

export 'port_audio_common.dart';
export 'port_audio_constant.dart';

void paLog(Object? message) {
  // ignore: avoid_print
  print(message);
}

/// PortAudio stream
final class PaStream extends Opaque {}

/// PortAudio error code
typedef PaError = Int32;

// Can be ignored
// typedef enum PaErrorCode
// {
//     paNoError = 0,
//
//     paNotInitialized = -10000,
//     paUnanticipatedHostError,
//     paInvalidChannelCount,
//     paInvalidSampleRate,
//     paInvalidDevice,
//     paInvalidFlag,
//     paSampleFormatNotSupported, -9994
//     paBadIODeviceCombination, -9993
//     paInsufficientMemory,
//     paBufferTooBig,
//     paBufferTooSmall, -9990
//     paNullCallback,
//     paBadStreamPtr,
//     paTimedOut,
//     paInternalError,
//     paDeviceUnavailable,
//     paIncompatibleHostApiSpecificStreamInfo,
//     paStreamIsStopped,
//     paStreamIsNotStopped,
//     paInputOverflowed,
//     paOutputUnderflowed, -9980
//     paHostApiNotFound,
//     paInvalidHostApi,
//     paCanNotReadFromACallbackStream,
//     paCanNotWriteToACallbackStream,
//     paCanNotReadFromAnOutputOnlyStream,
//     paCanNotWriteToAnInputOnlyStream,
//     paIncompatibleStreamHostApi,
//     paBadBufferPtr,
//     paCanNotInitializeRecursively
// } PaErrorCode;

// typedef unsigned long PaSampleFormat;
//
//
// #define paFloat32        ((PaSampleFormat) 0x00000001) /**< @see PaSampleFormat */
// #define paInt32          ((PaSampleFormat) 0x00000002) /**< @see PaSampleFormat */
// #define paInt24          ((PaSampleFormat) 0x00000004) /**< Packed 24 bit format. @see PaSampleFormat */
// #define paInt16          ((PaSampleFormat) 0x00000008) /**< @see PaSampleFormat */
// #define paInt8           ((PaSampleFormat) 0x00000010) /**< @see PaSampleFormat */
// #define paUInt8          ((PaSampleFormat) 0x00000020) /**< @see PaSampleFormat */
// #define paCustomFormat   ((PaSampleFormat) 0x00010000) /**< @see PaSampleFormat */
typedef PaErrorDart = int;
typedef PaSampleFormat = Uint64;
typedef PaSampleFormatDart = int;

typedef PaTime = Double;
typedef PaTimeDart = double;

const PaSampleFormatDart paFormatFloat32 = 0x00000001;

typedef PaDeviceIndex = Int32;
typedef PaDeviceIndexDart = int;
typedef PaStreamCallback =
    Int32 Function(
      Pointer<Void> input,
      Pointer<Void> output,
      Int32 frameCount,
      Pointer<Void> timeInfo,
      Int32 statusFlags,
      Pointer<Void> userData,
    );

sealed class PaDeviceInfo extends Struct {
  @Int32()
  external int structVersion;
  external Pointer<Utf8> name;
  @Int32()
  external int hostApi;
  @Int32()
  external int maxInputChannels;
  @Int32()
  external int maxOutputChannels;
  @Double()
  external double defaultLowInputLatency;
  @Double()
  external double defaultLowOutputLatency;
  @Double()
  external double defaultHighInputLatency;
  @Double()
  external double defaultHighOutputLatency;
}

sealed class PaStreamInfo extends Struct {
  /// this is struct version 1
  @Int32()
  external int structVersion;

  /// The input latency of the stream in seconds. This value provides the most
  /// accurate estimate of input latency available to the implementation. It may
  /// differ significantly from the suggestedLatency value passed to Pa_OpenStream().
  /// The value of this field will be zero (0.) for output-only streams.
  /// @see PaTime
  @Double()
  external double inputLatency;

  /// The output latency of the stream in seconds. This value provides the most
  ///
  /// accurate estimate of output latency available to the implementation. It may
  /// differ significantly from the suggestedLatency value passed to Pa_OpenStream().
  /// The value of this field will be zero (0.) for input-only streams.
  /// @see PaTime
  @Double()
  external double outputLatency;

  /// The sample rate of the stream in Hertz (samples per second). In cases
  /// where the hardware sample rate is inaccurate and PortAudio is aware of it,
  /// the value of this field may be different from the sampleRate parameter
  /// passed to Pa_OpenStream(). If information about the actual hardware sample
  /// rate is not available, this field will have the same value as the sampleRate
  /// parameter passed to Pa_OpenStream().
  @Double()
  external double sampleRate;

  @override
  String toString() {
    return 'PaStreamInfo{structVersion: $structVersion, inputLatency: $inputLatency, outputLatency: $outputLatency, sampleRate: $sampleRate}';
  }
}

typedef PaStreamCallbackDart =
    Int32 Function(
      Pointer<Void> input,
      Pointer<Void> output,
      Int32 frameCount,
      Pointer<Void> timeInfo,
      Int32 statusFlags,
      Pointer<Void> userData,
    );
typedef PaInitialize = PaError Function();
typedef PaInitializeDart = PaErrorDart Function();
typedef PaTerminate = PaError Function();
typedef PaTerminateDart = PaErrorDart Function();
typedef PaOpenDefaultStream =
    PaError Function(
      Pointer<Pointer<PaStream>> stream,
      Int32 numInputChannels,
      Int32 numOutputChannels,
      PaSampleFormat sampleFormat,
      Double sampleRate,
      Int32 framesPerBuffer,
      Pointer<NativeFunction<PaStreamCallback>> callback,
      Pointer<Void> userData,
    );
typedef PaOpenDefaultStreamDart =
    PaErrorDart Function(
      Pointer<Pointer<PaStream>> stream,
      int numInputChannels,
      int numOutputChannels,
      PaSampleFormatDart sampleFormat,
      double sampleRate,
      int framesPerBuffer,
      Pointer<NativeFunction<PaStreamCallback>> callback,
      Pointer<Void> userData,
    );
typedef PaStartStream = PaError Function(Pointer<PaStream> stream);
typedef PaStartStreamDart = PaErrorDart Function(Pointer<PaStream> stream);
typedef PaGetStreamWriteAvailable = Int64 Function(Pointer<PaStream> stream);
typedef PaGetStreamWriteAvailableDart = int Function(Pointer<PaStream> stream);

typedef PaGetDeviceCount = PaDeviceIndex Function();
typedef PaGetDeviceCountDart = PaDeviceIndexDart Function();
typedef PaGetDefaultOutputDevice = PaDeviceIndex Function();
typedef PaGetDefaultOutputDeviceDart = PaDeviceIndexDart Function();
typedef PaGetDeviceInfo = Pointer<PaDeviceInfo> Function(PaDeviceIndex index);
typedef PaGetDeviceInfoDart =
    Pointer<PaDeviceInfo> Function(PaDeviceIndexDart index);
typedef PaCloseStream = PaError Function(Pointer<PaStream> stream);
typedef PaCloseStreamDart = PaErrorDart Function(Pointer<PaStream> stream);
typedef PaStopStream = PaError Function(Pointer<PaStream> stream);
typedef PaStopStreamDart = PaErrorDart Function(Pointer<PaStream> stream);
typedef PaAbortStream = PaError Function(Pointer<PaStream> stream);
typedef PaAbortStreamDart = PaErrorDart Function(Pointer<PaStream> stream);
typedef PaIsStreamActive = PaError Function(Pointer<PaStream> stream);
typedef PaIsStreamActiveDart = PaErrorDart Function(Pointer<PaStream> stream);
typedef PaGetStreamInfo =
    Pointer<PaStreamInfo> Function(Pointer<PaStream> stream);
typedef PaGetStreamInfoDart =
    Pointer<PaStreamInfo> Function(Pointer<PaStream> stream);
typedef PaGetStreamTime = PaTime Function(Pointer<PaStream> stream);
typedef PaGetStreamTimeDart = PaTimeDart Function(Pointer<PaStream> stream);
typedef PaWriteStream =
    Int32 Function(
      Pointer<PaStream> stream,
      Pointer<Void> buffer,
      Int32 frames,
    );
typedef PaWriteStreamDart =
    int Function(Pointer<PaStream> stream, Pointer<Void> buffer, int frames);

class PortAudioNativeLib {
  final DynamicLibrary _nativeLib;

  PortAudioNativeLib._(this._nativeLib);

  late final initialize = _nativeLib
      .lookupFunction<PaInitialize, PaInitializeDart>('Pa_Initialize');
  late final terminate = _nativeLib
      .lookupFunction<PaInitialize, PaInitializeDart>('Pa_Terminate');
  late final openDefaultStream = _nativeLib
      .lookupFunction<PaOpenDefaultStream, PaOpenDefaultStreamDart>(
        'Pa_OpenDefaultStream',
      );
  late final closeStream = _nativeLib
      .lookupFunction<PaCloseStream, PaCloseStreamDart>('Pa_CloseStream');
  late final startStream = _nativeLib
      .lookupFunction<PaStartStream, PaStartStreamDart>('Pa_StartStream');

  late final getDeviceCount = _nativeLib
      .lookupFunction<PaGetDeviceCount, PaGetDeviceCountDart>(
        'Pa_GetDeviceCount',
      );
  late final getDefaultOutputDevice = _nativeLib
      .lookupFunction<PaGetDefaultOutputDevice, PaGetDefaultOutputDeviceDart>(
        'Pa_GetDefaultOutputDevice',
      );

  /// Retrieve a pointer to a PaDeviceInfo structure containing information
  /// about the specified device.
  /// @return A pointer to an immutable PaDeviceInfo structure. If the device
  /// parameter is out of range the function returns NULL.
  ///
  /// @param device A valid device index in the range 0 to (Pa_GetDeviceCount()-1)
  ///
  /// @note PortAudio manages the memory referenced by the returned pointer,
  /// the client must not manipulate or free the memory. The pointer is only
  /// guaranteed to be valid between calls to Pa_Initialize() and Pa_Terminate().
  ///
  /// @see PaDeviceInfo, PaDeviceIndex
  late final getDeviceInfo = _nativeLib
      .lookupFunction<PaGetDeviceInfo, PaGetDeviceInfoDart>('Pa_GetDeviceInfo');

  //  Terminates audio processing. It waits until all pending
  //  audio buffers have been played before it returns.
  late final stopStream = _nativeLib
      .lookupFunction<PaStopStream, PaStopStreamDart>('Pa_StopStream');

  // Terminates audio processing promptly without necessarily waiting for
  //  pending buffers to complete.
  late final abortStream = _nativeLib
      .lookupFunction<PaAbortStream, PaAbortStreamDart>('Pa_AbortStream');

  /// Retrieve a pointer to a PaStreamInfo structure containing information
  //  about the specified stream.
  //  @return A pointer to an immutable PaStreamInfo structure. If the stream
  //  parameter is invalid, or an error is encountered, the function returns NULL.
  //
  //  @param stream A pointer to an open stream previously created with Pa_OpenStream().
  //
  //  @note PortAudio manages the memory referenced by the returned pointer,
  //  the client must not manipulate or free the memory. The pointer is only
  //  guaranteed to be valid until the specified stream is closed.
  //
  //  @see PaStreamInfo
  //
  // const PaStreamInfo* Pa_GetStreamInfo( PaStream *stream );
  late final getStreamInfo = _nativeLib
      .lookupFunction<PaGetStreamInfo, PaGetStreamInfoDart>('Pa_GetStreamInfo');

  /// Returns the current time in seconds for a stream according to the same clock used
  //  to generate callback PaStreamCallbackTimeInfo timestamps. The time values are
  //  monotonically increasing and have unspecified origin.
  //
  //  Pa_GetStreamTime returns valid time values for the entire life of the stream,
  //  from when the stream is opened until it is closed. Starting and stopping the stream
  //  does not affect the passage of time returned by Pa_GetStreamTime.
  //
  //  This time may be used for synchronizing other events to the audio stream, for
  //  example synchronizing audio to MIDI.
  //
  //  @return The stream's current time in seconds, or 0 if an error occurred.
  //
  //  @see PaTime, PaStreamCallback, PaStreamCallbackTimeInfo
  //
  // PaTime Pa_GetStreamTime( PaStream *stream );
  late final getStreamTime = _nativeLib
      .lookupFunction<PaGetStreamTime, PaGetStreamTimeDart>('Pa_GetStreamTime');
  // Determine whether the stream is active.
  //  A stream is active after a successful call to Pa_StartStream(), until it
  //  becomes inactive either as a result of a call to Pa_StopStream() or
  //  Pa_AbortStream(), or as a result of a return value other than paContinue from
  //  the stream callback. In the latter case, the stream is considered inactive
  //  after the last buffer has finished playing.
  //
  //  @return Returns one (1) when the stream is active (ie playing or recording
  //  audio), zero (0) when not playing or, a PaErrorCode (which are always negative)
  //  if PortAudio is not initialized or an error is encountered.
  //
  //  @see Pa_StopStream, Pa_AbortStream, Pa_IsStreamStopped
  // PaError Pa_IsStreamActive( PaStream *stream );
  late final isStreamActive = _nativeLib
      .lookupFunction<PaIsStreamActive, PaIsStreamActiveDart>(
        'Pa_IsStreamActive',
      );

  // Write samples to an output stream. This function doesn't return until the
  //  entire buffer has been written - this may involve waiting for the operating
  //  system to consume the data.
  //
  //  Writing to a stream that is stopped is not currently supported. In particular,
  //  it is not possible to prefill the write buffer by calling Pa_WriteStream
  //  prior to calling Pa_StartStream().
  //
  //  @param stream A pointer to an open stream previously created with Pa_OpenStream().
  //
  //  @param buffer A pointer to a buffer of sample frames. The buffer contains
  //  samples in the format specified by the outputParameters->sampleFormat field
  //  used to open the stream, and the number of channels specified by
  //  outputParameters->numChannels. If non-interleaved samples were requested using
  //  the paNonInterleaved sample format flag, buffer is a pointer to the first element
  //  of an array of buffer pointers, one non-interleaved buffer for each channel.
  //
  //  @param frames The number of frames to be written from buffer. This parameter
  //  is not constrained to a specific range, however high performance applications
  //  will want to match this parameter to the framesPerBuffer parameter used
  //  when opening the stream.
  //
  //  @return On success PaNoError will be returned, or paOutputUnderflowed if
  //  additional output data was inserted after the previous call and before this
  //  call.
  // */
  // PaError Pa_WriteStream( PaStream* stream,
  //                         const void *buffer,
  //                         unsigned long frames );
  late final writeStream = _nativeLib
      .lookupFunction<PaWriteStream, PaWriteStreamDart>('Pa_WriteStream');

  /// Retrieve the number of frames that can be written to the stream without
  /// waiting.

  /// When the stream is stopped the return value of Pa_GetStreamWriteAvailable is not
  /// defined.

  /// @return Returns a non-negative value representing the maximum number of frames
  /// that can be written to the stream without blocking or busy waiting or, a
  /// PaErrorCode (which are always negative) if PortAudio is not initialized or an
  /// error is encountered.
  ///
  /// signed long Pa_GetStreamWriteAvailable( PaStream* stream );
  late final getStreamWriteAvailable = _nativeLib
      .lookupFunction<PaGetStreamWriteAvailable, PaGetStreamWriteAvailableDart>(
        'Pa_GetStreamWriteAvailable',
      );
}

/// Load PortAudio shared library
Future<DynamicLibrary> _loadDynamicLibrary({String? path}) async {
  try {
    if (path != null) {
      return DynamicLibrary.open(path);
    }
  } catch (_) {
    stderr.writeln('Failed to load portaudio library at $path');
    rethrow;
  }
  if (Platform.isLinux) {
    try {
      return DynamicLibrary.open('libportaudio.so');
    } catch (e) {
      stderr.writeln(
        'Failed to load portaudio library\n'
        'Please install portaudio:\n'
        '  sudo apt-get install portaudio19-dev',
      );
      rethrow;
    }
  } else if (Platform.isMacOS) {
    try {
      return DynamicLibrary.open('/opt/local/lib/libportaudio.dylib');
    } catch (e) {
      stderr.writeln(
        'Failed to load portaudio library\n'
        'Please install portaudio:\n'
        '  sudo port install portaudio',
      );
      rethrow;
    }
  } else if (Platform.isWindows) {
    var path = './.local/lib/libportaudio64bit.dll';
    if (!File(path).existsSync()) {
      var uri = Uri.parse(
        'https://github.com/spatialaudio/portaudio-binaries/raw/refs/heads/master/libportaudio64bit.dll',
      );
      await httpClientFactoryIo.downloadFile(uri, path: path);
    }

    try {
      return DynamicLibrary.open(path);
    } catch (e) {
      stderr.writeln(
        'Failed to load portaudio library\n'
        'Please install and specify a portaudio dll path',
      );
      rethrow;
    }
  } else {
    throw UnsupportedError('Platform not supported');
  }
}

PortAudioNativeLib? _portAudioNativeLib;

final _lock = Lock();

/// Get PortAudio shared library can only be used once with a specific path
/// Subsequent calls will return the same instance
Future<PortAudioNativeLib> getPortAudioNativeLib({String? path}) async {
  _portAudioNativeLib ??= await _lock.synchronized(() async {
    return PortAudioNativeLib._(await _loadDynamicLibrary(path: path));
  });
  return _portAudioNativeLib!;
}
