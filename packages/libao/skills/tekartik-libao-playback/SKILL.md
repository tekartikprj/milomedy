---
name: tekartik-libao-playback
description: >-
  Use when playing raw PCM samples, or writing wav/au/raw files, from the Dart
  VM through the libao C library with tekartik_libao: Libao.open (library path
  per platform), initialize/shutdown, defaultDriverId, driverId ('pulse',
  'alsa', 'wav', 'null'), driverInfo/driverInfoList (Info, OutputType),
  openLive/openFile (bits, rate, channels, ByteFormat, matrix),
  Device.initialized, play(device, Uint8List interleaved samples), close, the
  AoOption/appendOption/freeOptions driver options and the
  package:tekartik_libao/libao.dart import.
---

# libao playback (tekartik_libao)

`tekartik_libao` is a thin `dart:ffi` wrapper over the libao `ao_*` functions:
initialize, pick a driver, open a live device or an output file, push
interleaved PCM bytes, close. Everything is synchronous and blocking, and it
only runs where `dart:ffi` and `dart:io` exist (Dart VM, Flutter desktop and
mobile), never on the web.

## Guidelines

* Dependency (git, not on pub.dev):
  ```yaml
  dependencies:
    tekartik_libao:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/libao
    ffi: ">=2.1.4" # calloc, toNativeUtf8, nullptr for driver options
  ```
* Import `package:tekartik_libao/libao.dart`: it exports `Libao`, `Device`,
  `Info`, `OutputType`, `ByteFormat` and the `AoOption` struct.
* Native library: libao must be installed (`sudo apt install libao4` on
  Debian/Ubuntu, `brew install libao` on macOS). `Libao.open()` without an
  argument only knows the Linux path `/usr/lib/x86_64-linux-gnu/libao.so.4`;
  on every other platform (and on non x86_64 Linux) pass the path yourself:
  `Libao.open('/opt/homebrew/lib/libao.dylib')`,
  `Libao.open(r'bin\libao.dll')` (a `libao.dll` ships in the package `bin/`
  folder). Without a loadable path the factory throws.
* Lifecycle, in this order: `ao.initialize()` once, driver lookups,
  `openLive`/`openFile`, one or more `play`, `close(device)` for every
  device, `ao.shutdown()` before exit. Do not use a `Libao` after
  `shutdown()`.
* Drivers: `defaultDriverId()` is the default live driver (pulse, alsa,
  macosx...). `driverId('wav')`, `'au'` and `'raw'` are file drivers,
  `'null'` discards audio (tests without a sound card), `'pulse'`, `'alsa'`,
  `'oss'`... are live drivers; the call returns a negative id for an unknown
  driver. `driverInfo(id)` returns an `Info` (`type` is `OutputType.live` or
  `OutputType.file`, `name`, `shortName`, `comment`, `byteFormat`,
  `priority`), `driverInfoList()` lists every driver.
* `openLive(driverId, {bits = 16, rate = 44100, channels = 2, byteFormat =
  ByteFormat.little, matrix, options})` and `openFile(driverId, filename,
  {same format parameters})` return a `Device`. Always check
  `device.initialized`: `false` means libao returned NULL (device busy,
  unknown driver, unsupported format) and the device must not be used.
  `openFile` always overwrites the file and takes no options.
* `play(device, Uint8List samples)` copies the bytes to native memory and
  blocks until libao accepted them; it returns `false` on failure. Samples
  are interleaved by channel, `bits ~/ 8` bytes each, in the byte order given
  by `byteFormat` (`ByteFormat.little`: low byte first). One second of 16 bit
  stereo at 44100 Hz is `2 * 2 * 44100` bytes: feed the device in chunks of
  that order of magnitude rather than one huge buffer.
* `matrix` is the libao channel matrix string describing the channel order of
  your samples (`'L,R'`, `'M'`...); leave it null for the driver default.
* Driver options are a native `ao_option` linked list: allocate the head with
  `calloc<AoOption>()`, set `key`/`value` with `toNativeUtf8()` and `next =
  nullptr`, add the following ones with `appendOption(options, key, value)`
  (it appends to the end, the head pointer stays valid; do not start from
  `nullptr`), pass `options:` to `openLive`, then `freeOptions(options)` once
  the device is open. Keys depend on the driver (`'dev'`, `'id'`,
  `'client_name'`, `'debug'`... see the libao driver documentation).
* The wrapper never frees the native strings it allocates for
  `driverId(shortname)`, `matrix` and `filename`, and libao gives no error
  message: keep those calls out of hot loops and check `initialized`.
* Testing: the package has no test suite. Use the `'null'` driver, or
  `openFile(driverId('wav'), path)` and inspect the file, so tests do not
  depend on a sound device.

## Examples

### Play one second of a 440 Hz sine on the default driver

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:tekartik_libao/libao.dart';

/// Interleaved 16 bit little endian stereo samples, [seconds] long.
Uint8List sineStereo16({
  double freq = 440,
  double volume = 0.5,
  int rate = 44100,
  int seconds = 1,
}) {
  var frames = rate * seconds;
  var buffer = Uint8List(frames * 2 * 2); // 2 channels * 2 bytes
  var data = ByteData.view(buffer.buffer);
  for (var i = 0; i < frames; i++) {
    var sample = (volume * 32767 * sin(2 * pi * freq * i / rate)).round();
    data.setInt16(i * 4, sample, Endian.little); // left
    data.setInt16(i * 4 + 2, sample, Endian.little); // right
  }
  return buffer;
}

void main() {
  // Libao.open('/opt/homebrew/lib/libao.dylib') outside x86_64 Linux.
  final ao = Libao.open();
  ao.initialize();
  try {
    final driverId = ao.defaultDriverId();
    print(ao.driverInfo(driverId));
    final device = ao.openLive(driverId, bits: 16, channels: 2, rate: 44100);
    if (!device.initialized) {
      print('error opening the default device');
      return;
    }
    ao.play(device, sineStereo16());
    ao.close(device);
  } finally {
    ao.shutdown();
  }
}
```

### Write a wav file with the file driver

```dart
import 'dart:typed_data';

import 'package:tekartik_libao/libao.dart';

/// [mono16Samples]: 16 bit little endian mono samples.
void writeWav(
  Libao ao,
  String path,
  Uint8List mono16Samples, {
  int rate = 22050,
}) {
  var driverId = ao.driverId('wav');
  if (driverId < 0) {
    throw StateError('wav driver not available');
  }
  var device = ao.openFile(driverId, path, bits: 16, channels: 1, rate: rate);
  if (!device.initialized) {
    throw StateError('cannot open $path');
  }
  ao.play(device, mono16Samples);
  ao.close(device);
}
```

### List the drivers and open one with options

```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:tekartik_libao/libao.dart';

void main() {
  final ao = Libao.open();
  ao.initialize();
  for (var info in ao.driverInfoList()) {
    print('${info.shortName} (${info.type.name}): ${info.name}');
  }

  // Options are a native linked list: allocate the head, append the rest.
  final options = calloc<AoOption>();
  options.ref.key = 'client_name'.toNativeUtf8();
  options.ref.value = 'my_app'.toNativeUtf8();
  options.ref.next = nullptr;
  ao.appendOption(options, 'debug', '');

  final device = ao.openLive(ao.driverId('pulse'), options: options);
  ao.freeOptions(options);
  if (device.initialized) {
    // ao.play(device, samples);
    ao.close(device);
  }
  ao.shutdown();
}
```

## Common mistakes

* Calling `Libao.open()` without a path on macOS or Windows.
* Using a `Device` whose `initialized` is false.
* Passing planar (per channel) buffers: `play` expects interleaved frames.
* Forgetting `close(device)` and `shutdown()`, which leaves the device busy
  for the next process.
* Building the option list from `nullptr` instead of a `calloc`ed head.
