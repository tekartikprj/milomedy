// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'package:tekartik_libao/libao.dart';

void main() {
  final ao = Libao.open();
  //final ao = Libao.open('../bin/libao.dll');

  ao.initialize();

  final driverId = ao.defaultDriverId();
  print('driverId: $driverId');
  const bits = 16;
  const channels = 2;
  const rate = 44100;

  print(ao.driverInfo(driverId));

  final options = calloc<AoOption>();
  options.ref.key = 'id'.toNativeUtf8();
  options.ref.value = '0'.toNativeUtf8();
  options.ref.next = nullptr;

  ao.appendOption(options, 'debug', '');

  final device = ao.openLive(driverId, options: options);

  ao.freeOptions(options);

  if (!device.initialized) {
    print('ERROR Opening the device');
    ao.shutdown();
    return;
  }

  const volume = 0.5;
  const freq = 440.0;

  // Number of bytes * Channels * Sample rate.
  const bufferSize = bits ~/ 8 * channels * rate;
  final buffer = Uint8List(bufferSize);

  for (var i = 0; i < rate; i++) {
    final sample = (volume * 32768.0 * sin(2 * pi * freq * (i / rate))).round();
    // Left = Right.
    buffer[4 * i] = buffer[4 * i + 2] = sample & 0xff;
    buffer[4 * i + 1] = buffer[4 * i + 3] = (sample >> 8) & 0xff;
  }

  ao.play(device, buffer);

  ao.close(device);
  ao.shutdown();
}

Uint8List generateBuffer1({int bits = 16, int channels = 2, int rate = 44100}) {
  const volume = 0.5;
  const freq = 440.0;

  // Number of bytes * Channels * Sample rate.
  final bufferSize = bits ~/ 8 * channels * rate;
  final buffer = Uint8List(bufferSize);

  for (var i = 0; i < rate; i++) {
    final sample = (volume * 32768.0 * sin(2 * pi * freq * (i / rate))).round();
    // Left = Right.
    buffer[4 * i] = buffer[4 * i + 2] = sample & 0xff;
    buffer[4 * i + 1] = buffer[4 * i + 3] = (sample >> 8) & 0xff;
  }
  return buffer;
}
