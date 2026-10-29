// ignore_for_file: avoid_print

@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_platform_io/util/github_util.dart';
import 'package:tekartik_port_audio/port_audio.dart';
import 'package:test/test.dart';

Future<void> main() async {
  // GitHub runners have no sound card: since the 2026-10 ubuntu-24.04 images,
  // the system PortAudio aborts in Pa_Initialize there, and the CI does not
  // install it, so run locally only (before loading the library).
  var skip = platformIo.runningOnGithub;
  if (skip) {
    test(
      'skipping port_audio on github for ${Platform.operatingSystem}',
      () {},
    );
    return;
  }
  var portAudioLib = await getPortAudioLib();

  setUpAll(() async {
    var err = await portAudioLib.initialize();
    print('PortAudio.initialize err: $err');
  });
  test('getDeviceInfo', () async {
    var count = await portAudioLib.getDeviceCount();
    print('PortAudio.getDeviceCount(): $count');
    var index = await portAudioLib.getDefaultOutputDevice();
    print('PortAudio.getDefaultOutputDevice(): $index');
    for (var i = 0; i < count; i++) {
      var info = await portAudioLib.getDeviceInfo(i);
      if (info.maxOutputChannels > 0) {
        print('device${i == index ? ' (default)' : ''}: ${info.name}');
        print('  maxOutputChannels: ${info.maxOutputChannels}');
        print('  defaultLowOutputLatency: ${info.defaultLowOutputLatency}');
        print('  defaultHighOutputLatency: ${info.defaultHighOutputLatency}');
      }
    }
  });
}
