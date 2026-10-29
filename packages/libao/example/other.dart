// ignore_for_file: avoid_print

import 'dart:math';
import 'dart:typed_data';

import 'package:tekartik_libao/libao.dart';

import 'main.dart';

void main() {
  final ao = Libao.open();

  ao.initialize();

  final driverId = ao.defaultDriverId();

  print(ao.driverInfo(driverId));

  const bits = 16;
  const channels = 2;
  const rate = 44100;

  final device = ao.openLive(
    driverId,
    bits: bits,
    channels: channels,
    rate: rate,
    matrix: 'R',
  );
  if (!device.initialized) {
    print('ERROR Opening the device');
    ao.shutdown();
    return;
  }

  const volume = 0.5;
  const freq = 230.0;

  // Number of bytes * Channels * Sample rate.
  const bufferSize = bits ~/ 8 * channels * rate;
  final buffer = Uint8List(bufferSize);

  for (var i = 0; i < rate; i++) {
    final sample = (volume * 32768.0 * sin(2 * pi * freq * (i / rate))).round();
    // Left = Right.
    buffer[4 * i] = buffer[4 * i + 2] = sample & 0xff;
    buffer[4 * i + 1] = buffer[4 * i + 3] = (sample >> 8) & 0xff;
  }

  print('Playing buffer 1');
  ao.play(device, buffer);
  print('Playing buffer 2');
  var buffer2 = generateBuffer1();
  ao.play(device, buffer2);
  ao.close(device);
  ao.shutdown();
}
