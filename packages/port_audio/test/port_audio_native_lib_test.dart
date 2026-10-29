// ignore_for_file: avoid_print

@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:tekartik_platform_io/util/github_util.dart';
import 'package:tekartik_port_audio/src/port_audio_native_lib.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var portAudioNativeLib = await getPortAudioNativeLib();
  var skip = platformIo.runningOnGithub && !Platform.isLinux;
  if (skip) {
    test(
      'skipping port_audio on github for ${Platform.operatingSystem}',
      () {},
    );
    return;
  }

  setUpAll(() async {
    var err = portAudioNativeLib.initialize();
    print('PortAudio.initialize err: $err');
  });
  test('getDeviceInfo', () async {
    var count = portAudioNativeLib.getDeviceCount();
    print('PortAudio.getDeviceCount(): $count');
    var defaultIndex = portAudioNativeLib.getDefaultOutputDevice();
    print('PortAudio.getDefaultOutputDevice(): $defaultIndex');
    for (var i = 0; i < count; i++) {
      var pointer = portAudioNativeLib.getDeviceInfo(i);
      var info = pointer.ref;
      print(
        'device${i == defaultIndex ? ' (default)' : ''}: ${info.name.toDartString()}',
      );
      print('  maxOutputChannels: ${info.maxOutputChannels}');
      print('  defaultLowOutputLatency: ${info.defaultLowOutputLatency}');
      print('  defaultHighOutputLatency: ${info.defaultHighOutputLatency}');
    }
  });
  tearDownAll(() async {
    var err = portAudioNativeLib.terminate();
    print('PortAudio.initialize err: $err');
  });
}
