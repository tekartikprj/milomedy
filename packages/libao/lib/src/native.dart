import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

base class _Device extends Opaque {}

/// Represents an open device.
class Device {
  final Pointer<_Device> _device;

  Device._(this._device);

  /// checkes whether the device has been successfully initialized or is NULL due to an ERROR
  ///
  /// ```dart
  /// final device = ao.openLive(driverId, options:options);
  /// if(!device.initialized) {
  ///   // an error occured
  /// }
  /// ```
  bool get initialized => _device.address != 0;
}

base class _Info extends Struct {
  @Int32()
  external int type;
  external Pointer<Utf8> name;
  external Pointer<Utf8> shortName;
  external Pointer<Utf8> author;
  external Pointer<Utf8> comment;
  @Int32()
  external int byteFormat;
  @Int32()
  external int priority;
  external Pointer<Pointer<Utf8>> options;
  @Int32()
  external int optionCount;
}

/// Holds the attributes of an output driver
class Info {
  /// The output type of the driver.
  final OutputType type;

  /// A longer name for the driver.
  final String name;

  /// A short identifier for the driver.
  final String shortName;

  /// The driver author.
  final String author;

  /// Driver comment.
  final String comment;

  /// Specifies the preferred ordering of the sample bytes.
  final int? byteFormat;

  /// A positive integer ranking how likely it is for this driver to be the default.
  final int? priority;

  Info._(_Info info)
    : type = _intToOutputType(info.type),
      name = info.name.toDartString(),
      shortName = info.shortName.toDartString(),
      author = info.author.toDartString(),
      comment = info.comment.toDartString(),
      byteFormat = info.byteFormat,
      priority = info.priority;

  @override
  String toString() {
    return 'Info {type: $type, name: $name, shortName: $shortName, author: $author, comment: $comment, byteFormat: $byteFormat, priority: $priority}';
  }
}

base class _SampleFormat extends Struct {
  @Int32()
  external int bits;
  @Int32()
  external int rate;
  @Int32()
  external int channels;
  @Int32()
  external int byteFormat;
  external Pointer<Utf8> matrix;
}

/// A linked list element holding the Key-Value pair of a driver option
base class AoOption extends Struct {
  /// The Key of the Key-Value Pair
  external Pointer<Utf8> key;

  /// The Value of the Key-Value Pair
  external Pointer<Utf8> value;

  /// The Pointer to the next element in the linked list
  /// nullptr if this is the last element in the list
  external Pointer<AoOption> next;
}

typedef _InitializeNative = Void Function();
typedef _Initialize = void Function();

typedef _ShutdownNative = Void Function();
typedef _Shutdown = void Function();

typedef _DriverIdNative = Int32 Function(Pointer<Utf8> shortName);
typedef _DriverId = int Function(Pointer<Utf8> shortName);

typedef _DefaultDriverIdNative = Int32 Function();
typedef _DefaultDriverId = int Function();

typedef _DriverInfoNative = Pointer<_Info> Function(Int32 driverId);
typedef _DriverInfo = Pointer<_Info> Function(int driverId);

typedef _DriverInfoListNative =
    Pointer<Pointer<_Info>> Function(Pointer<Int32> count);
typedef _DriverInfoList =
    Pointer<Pointer<_Info>> Function(Pointer<Int32> driverId);

typedef _OpenLiveNative =
    Pointer<_Device> Function(
      Int32 driverId,
      Pointer<_SampleFormat> sampleFormat,
      Pointer<AoOption> options,
    );
typedef _OpenLive =
    Pointer<_Device> Function(
      int driverId,
      Pointer<_SampleFormat> sampleFormat,
      Pointer<AoOption> options,
    );

typedef _OpenFileNative =
    Pointer<_Device> Function(
      Int32 driverId,
      Pointer<Utf8> filename,
      Int32 overwrite,
      Pointer<_SampleFormat> sampleFormat,
      Pointer<AoOption> options,
    );
typedef _OpenFile =
    Pointer<_Device> Function(
      int driverId,
      Pointer<Utf8> filename,
      int overwrite,
      Pointer<_SampleFormat> sampleFormat,
      Pointer<AoOption> options,
    );

typedef _PlayNative =
    Int32 Function(
      Pointer<_Device> device,
      Pointer<Int8> samples,
      Int32 length,
    );
typedef _Play =
    int Function(Pointer<_Device> device, Pointer<Int8> samples, int length);

typedef _CloseNative = Int32 Function(Pointer<_Device> device);
typedef _Close = int Function(Pointer<_Device> device);

typedef _FreeOptionsNative = Void Function(Pointer<AoOption> options);
typedef _FreeOptions = void Function(Pointer<AoOption> options);

typedef _AppendOptionNative =
    Int32 Function(
      Pointer<Pointer<AoOption>> options,
      Pointer<Utf8> key,
      Pointer<Utf8> value,
    );
typedef _AppendOption =
    int Function(
      Pointer<Pointer<AoOption>> options,
      Pointer<Utf8> key,
      Pointer<Utf8> value,
    );

/// The output type of the driver.
enum OutputType {
  /// Live output.
  live,

  /// File output.
  file,
}

OutputType _intToOutputType(int? outputType) {
  return outputType == 2 ? OutputType.file : OutputType.live;
}

/// The ordering of a sample byte.
enum ByteFormat {
  /// Samples are in little-endian order.
  little,

  /// Samples are in big-endian order.
  big,

  /// Samples are in the native ordering of the computer.
  native,
}

int _byteFormatToInt(ByteFormat byteFormat) {
  if (byteFormat == ByteFormat.big) return 2;
  if (byteFormat == ByteFormat.native) return 4;
  return 1;
}

/// Wraps the libao library.
class Libao {
  final DynamicLibrary _lib;
  late _Initialize _initialize;
  late _Shutdown _shutdown;
  late _DriverId _driverId;
  late _DefaultDriverId _defaultDriverId;
  late _DriverInfo _driverInfo;
  late _DriverInfoList _driverInfoList;
  late _OpenLive _openLive;
  late _OpenFile _openFile;
  late _Play _play;
  late _Close _close;
  late _FreeOptions _freeOptions;
  late _AppendOption _appendOption;

  Libao._(this._lib) {
    _initialize = _lib.lookupFunction<_InitializeNative, _Initialize>(
      'ao_initialize',
    );

    _shutdown = _lib.lookupFunction<_ShutdownNative, _Shutdown>('ao_shutdown');
    _driverId = _lib.lookupFunction<_DriverIdNative, _DriverId>('ao_driver_id');

    _defaultDriverId = _lib
        .lookupFunction<_DefaultDriverIdNative, _DefaultDriverId>(
          'ao_default_driver_id',
        );

    _driverInfo = _lib.lookupFunction<_DriverInfoNative, _DriverInfo>(
      'ao_driver_info',
    );

    _driverInfoList = _lib
        .lookupFunction<_DriverInfoListNative, _DriverInfoList>(
          'ao_driver_info_list',
        );

    _openLive = _lib.lookupFunction<_OpenLiveNative, _OpenLive>('ao_open_live');
    _openFile = _lib.lookupFunction<_OpenFileNative, _OpenFile>('ao_open_file');
    _play = _lib.lookupFunction<_PlayNative, _Play>('ao_play');
    _close = _lib.lookupFunction<_CloseNative, _Close>('ao_close');
    _freeOptions = _lib.lookupFunction<_FreeOptionsNative, _FreeOptions>(
      'ao_free_options',
    );
    _appendOption = _lib.lookupFunction<_AppendOptionNative, _AppendOption>(
      'ao_append_option',
    );
  }

  /// The paths tried by [Libao.open] when none is given, by platform: where
  /// the system packages and Homebrew install libao.
  static List<String> get defaultPaths {
    if (Platform.isMacOS) {
      return [
        // Homebrew on Apple silicon, then on Intel.
        '/opt/homebrew/lib/libao.4.dylib',
        '/usr/local/lib/libao.4.dylib',
        'libao.4.dylib',
      ];
    } else if (Platform.isLinux) {
      return [
        '/usr/lib/x86_64-linux-gnu/libao.so.4',
        '/usr/lib/aarch64-linux-gnu/libao.so.4',
        'libao.so.4',
      ];
    } else if (Platform.isWindows) {
      return ['libao.dll'];
    }
    return [];
  }

  /// Loads the libao library at [path], or at the first of [defaultPaths]
  /// that loads.
  factory Libao.open([String? path]) {
    if (path != null && path.isNotEmpty) {
      return Libao._(DynamicLibrary.open(path));
    }
    for (var candidate in defaultPaths) {
      try {
        return Libao._(DynamicLibrary.open(candidate));
      } on ArgumentError catch (_) {
        // Not there, try the next one.
      }
    }
    throw StateError(
      'libao not found in ${defaultPaths.join(', ')}: install it '
      '(brew install libao, apt install libao4) or give its path',
    );
  }

  /// Initializes the internal libao data structures and loads all of the available plugins.
  void initialize() => _initialize();

  /// unloads all of the plugins and deallocates any internal data structures the library has created.
  /// It should be called prior to program exit.
  void shutdown() => _shutdown();

  /// Looks up the ID number for a driver based upon its [shortname].
  ///
  /// The returned ID number is needed to open the driver or retrieve driver information.
  int driverId(String shortname) {
    return _driverId(shortname.toNativeUtf8());
  }

  /// Returns the ID number of the default live output driver.
  int defaultDriverId() => _defaultDriverId();

  /// Gets information about a particular driver.
  Info driverInfo(int id) {
    final pointer = _driverInfo(id);
    return Info._(pointer.ref);
  }

  /// Gets a list of information for all of the available drivers.
  List<Info> driverInfoList() {
    final res = <Info>[];
    final count = calloc<Int32>();
    final pointer = _driverInfoList(count);

    for (var i = 0; i < count.value; i++) {
      res.add(Info._((pointer + i).value.ref));
    }

    calloc.free(count);

    return res;
  }

  /// Opens a live playback audio device for output using [driverId].
  ///
  /// Accepts optional parameters [bits], [rate], [channels], [byteFormat], [matrix], and [options].
  /// Returns a [Device] instance.
  Device openLive(
    int driverId, {
    int bits = 16,
    int rate = 44100,
    int channels = 2,
    ByteFormat byteFormat = ByteFormat.little,
    String? matrix,
    Pointer<AoOption>? options,
  }) {
    final sampleFormat = calloc<_SampleFormat>();
    sampleFormat.ref.bits = bits;
    sampleFormat.ref.rate = rate;
    sampleFormat.ref.channels = channels;
    sampleFormat.ref.byteFormat = _byteFormatToInt(byteFormat);
    if (matrix != null) sampleFormat.ref.matrix = matrix.toNativeUtf8();

    final device = _openLive(
      driverId,
      sampleFormat,
      options ?? nullptr,
    ).address;

    calloc.free(sampleFormat);

    return Device._(Pointer.fromAddress(device));
  }

  /// Opens a file specified by [filename] for audio output using [driverId].
  ///
  /// Accepts optional parameters [bits], [rate], [channels], [byteFormat], and [matrix].
  /// Returns a [Device] instance.
  Device openFile(
    int driverId,
    String filename, {
    int bits = 16,
    int rate = 44100,
    int channels = 2,
    ByteFormat byteFormat = ByteFormat.little,
    String? matrix,
  }) {
    final sampleFormat = calloc<_SampleFormat>();
    sampleFormat.ref.bits = bits;
    sampleFormat.ref.rate = rate;
    sampleFormat.ref.channels = channels;
    sampleFormat.ref.byteFormat = _byteFormatToInt(byteFormat);
    if (matrix != null) sampleFormat.ref.matrix = matrix.toNativeUtf8();

    final device = _openFile(
      driverId,
      filename.toNativeUtf8(),
      1,
      sampleFormat,
      nullptr,
    ).address;

    calloc.free(sampleFormat);

    return Device._(Pointer.fromAddress(device));
  }

  /// Plays a block of audio [samples] to an open [device].
  ///
  /// Samples are interleaved by channels. Returns `true` if successful.
  bool play(Device device, Uint8List samples) {
    final data = calloc<Int8>(samples.lengthInBytes);

    for (var i = 0; i < samples.length; i++) {
      data[i] = samples[i];
    }

    try {
      return _play(device._device, data, samples.lengthInBytes) != 0;
    } finally {
      calloc.free(data);
    }
  }

  /// Closes the audio [device] and frees memory allocated by the device.
  ///
  /// Returns `true` if successful.
  bool close(Device device) => _close(device._device) != 0;

  /// Frees all memory allocated to an [options] list.
  void freeOptions(Pointer<AoOption> options) {
    _freeOptions(options);
  }

  /// Appends a [key] and [value] pair to an [options] linked list.
  ///
  /// Returns `true` if successful.
  bool appendOption(Pointer<AoOption> options, String key, String value) {
    final optionsPtr = calloc<Pointer<AoOption>>();
    optionsPtr.value = Pointer.fromAddress(options.address);
    return _appendOption(
          optionsPtr,
          key.toNativeUtf8(),
          value.toNativeUtf8(),
        ) ==
        1;
  }
}
