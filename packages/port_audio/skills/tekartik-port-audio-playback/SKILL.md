---
name: tekartik-port-audio-playback
description: >-
  Use when playing PCM audio from the Dart VM through PortAudio with
  tekartik_port_audio: getPortAudioLib and PortAudioLib (initialize,
  terminate, getDeviceCount, getDefaultOutputDevice, getDeviceInfo /
  PaDeviceInfo, defaultOutputStream), PortAudioOutputStream (open with
  PortAudioOutputStreamParameters numChannels/sampleRate/framesPerBuffer,
  start, writeDoubles, getWriteAvailable, getTime, getInfo / PaStreamInfo,
  stop, close), the paErrorCode* constants (paErrorCodeNoError,
  paErrorCodeOutputUnderflowed, paErrorCodeStreamNotOpened...),
  debugPortAudio, installing libportaudio (portaudio19-dev, MacPorts, the
  Windows dll download) and the worker-isolate design behind the async API.
---

# PortAudio playback (tekartik_port_audio)

`tekartik_port_audio` wraps the PortAudio C library (blocking write API,
float32 samples) for the Dart VM. The public API is fully asynchronous: every
call is forwarded to a worker isolate that owns the native handles, so the
blocking `Pa_WriteStream` never freezes your main isolate.

## Guidelines

* Dependency (git, `publish_to: none`):
  ```yaml
  dependencies:
    tekartik_port_audio:
      git:
        url: https://github.com/tekartikprj/milomedy
        path: packages/port_audio
  ```
* Native library: Linux loads `libportaudio.so` (`sudo apt-get install
  portaudio19-dev`), macOS `/opt/local/lib/libportaudio.dylib` (MacPorts:
  `sudo port install portaudio`), Windows downloads `libportaudio64bit.dll`
  into `./.local/lib/` from github.com/spatialaudio/portaudio-binaries on
  first use (network needed). Anything else: `getPortAudioLib(path:
  '/path/to/libportaudio.so')`. Other platforms throw `UnsupportedError`.
  The lib is a process singleton: the first call fixes the path, later calls
  return the same instance.
* Import `package:tekartik_port_audio/port_audio.dart`: `getPortAudioLib`,
  `PortAudioLib`, `PortAudioOutputStream`, `PortAudioOutputStreamParameters`,
  `debugPortAudio` and the `paErrorCode*` constants. `PaDeviceInfo` and
  `PaStreamInfo` are returned values, not constructible.
* Error handling is C style: methods return an `int` code and never throw for
  PortAudio errors. `paErrorCodeNoError` (0) is success, negative values are
  PortAudio `PaErrorCode`s (`paErrorCodeOutputUnderflowed`, -9980, is
  harmless on `writeDoubles`), and the package adds
  `paErrorCodeStreamNotOpened` (-998), `paErrorCodeStreamAlreadyOpened`
  (-997) and `paErrorCodeInvalidStream` (-999). `getDeviceCount()` and
  `getDefaultOutputDevice()` return the count/index or a negative error;
  `getDeviceInfo` and `getInfo` throw `StateError` on failure.
* Sequence: `var lib = await getPortAudioLib(); await lib.initialize();`,
  `var stream = lib.defaultOutputStream;` (every getter access creates a new
  unopened stream object: keep the reference), `await stream.open(parameters:
  PortAudioOutputStreamParameters(numChannels: 1, sampleRate: 44100,
  framesPerBuffer: 2048))`, `await stream.start()`, repeated
  `await stream.writeDoubles(samples)`, `await stream.stop()` (waits for the
  pending audio), `await stream.close()`, and finally `await lib.terminate()`.
* `terminate()` also ends the worker isolate (aborting still-open streams
  first). Call it once when the program is done: the singleton cannot be
  re-initialized afterwards in the same process.
* Samples: `writeDoubles(List<double>)` takes float32 values in -1.0..1.0 and
  completes once PortAudio consumed them. The list length is passed to
  PortAudio as the frame count, so with `numChannels: 1` one value per frame.
  With `numChannels > 1` the current implementation still uses the list
  length as the frame count (it does not divide by the channel count): down
  mix to mono until this is fixed. Write chunks of about `framesPerBuffer`
  frames (a few thousand), never one huge list: each call copies the list to
  the isolate and to native memory.
* `getWriteAvailable()` returns the frames writable without blocking (0 when
  not opened); `getTime()` the stream clock in seconds (monotonic, valid from
  open to close); `getInfo()` a `PaStreamInfo` (`inputLatency`,
  `outputLatency`, `sampleRate`).
* Set `debugPortAudio = true` before `initialize()` to log every native call
  from the worker (the flag travels with the initialize command).
* Low level: `package:tekartik_port_audio/src/port_audio_native_lib.dart`
  (`getPortAudioNativeLib`, `PortAudioNativeLib` with the raw `Pa_*`
  lookups, `PaStream`, `paFormatFloat32`) is what
  `example/native_example*.dart` and `test/port_audio_native_lib_test.dart`
  use. It is synchronous and blocks the calling isolate; prefer the public
  API.
* Tests: `dart test` (VM only, `@TestOn('vm')`); the tests skip on GitHub
  runners that are not Linux (`platformIo.runningOnGithub`). `example/`
  streams a C major scale that `example/example_sound.dart` writes once to
  `.local/` with `package:wav` (a dev dependency; add it to your own pubspec to
  read wav files).

## Examples

### List the output devices

```dart
import 'package:tekartik_port_audio/port_audio.dart';

Future<void> main() async {
  var lib = await getPortAudioLib();
  var err = await lib.initialize();
  if (err != paErrorCodeNoError) {
    throw StateError('PortAudio initialize failed: $err');
  }
  try {
    var count = await lib.getDeviceCount();
    var defaultIndex = await lib.getDefaultOutputDevice();
    for (var i = 0; i < count; i++) {
      var info = await lib.getDeviceInfo(i);
      if (info.maxOutputChannels > 0) {
        print(
          '${i == defaultIndex ? '*' : ' '} $i ${info.name} '
          '(${info.maxOutputChannels} ch, '
          'low latency ${info.defaultLowOutputLatency}s)',
        );
      }
    }
  } finally {
    await lib.terminate();
  }
}
```

### Play a generated tone in chunks

```dart
import 'dart:math';

import 'package:tekartik_port_audio/port_audio.dart';

Future<void> main() async {
  const sampleRate = 44100;
  const framesPerBuffer = 2048;
  var lib = await getPortAudioLib();
  var err = await lib.initialize();
  if (err != paErrorCodeNoError) {
    throw StateError('initialize: $err');
  }
  PortAudioOutputStream? stream;
  try {
    stream = lib.defaultOutputStream;
    err = await stream.open(
      parameters: PortAudioOutputStreamParameters(
        numChannels: 1,
        sampleRate: sampleRate.toDouble(),
        framesPerBuffer: framesPerBuffer,
      ),
    );
    if (err != paErrorCodeNoError) {
      throw StateError('open: $err');
    }
    print(await stream.getInfo());
    await stream.start();
    var frame = 0;
    var buffer = List<double>.filled(framesPerBuffer, 0);
    while (frame < sampleRate * 2) {
      // 2 seconds of 440 Hz
      for (var i = 0; i < framesPerBuffer; i++) {
        buffer[i] = 0.3 * sin(2 * pi * 440 * (frame++) / sampleRate);
      }
      err = await stream.writeDoubles(buffer);
      if (err != paErrorCodeNoError && err != paErrorCodeOutputUnderflowed) {
        throw StateError('write: $err');
      }
    }
    await stream.stop();
  } finally {
    await stream?.close();
    await lib.terminate();
  }
}
```

### Stream a wav file (package:wav)

```dart
import 'dart:io';

import 'package:tekartik_port_audio/port_audio.dart';
import 'package:wav/wav.dart';

Future<void> playWav(String path) async {
  var wav = await Wav.readFile(path);
  // Down mix to mono: writeDoubles counts one value per frame.
  var channels = wav.channels;
  var frameCount = channels.first.length;
  var mono = List<double>.generate(frameCount, (i) {
    var sum = 0.0;
    for (var channel in channels) {
      sum += channel[i];
    }
    return sum / channels.length;
  });

  var lib = await getPortAudioLib();
  if (await lib.initialize() != paErrorCodeNoError) {
    stderr.writeln('PortAudio initialize failed');
    return;
  }
  var stream = lib.defaultOutputStream;
  try {
    const chunk = 4096;
    await stream.open(
      parameters: PortAudioOutputStreamParameters(
        numChannels: 1,
        sampleRate: wav.samplesPerSecond.toDouble(),
        framesPerBuffer: chunk,
      ),
    );
    await stream.start();
    for (var i = 0; i < frameCount; i += chunk) {
      var end = i + chunk > frameCount ? frameCount : i + chunk;
      var available = await stream.getWriteAvailable();
      stdout.write('\r$available frames free, sending ${end - i}   ');
      await stream.writeDoubles(mono.sublist(i, end));
    }
    await stream.stop();
  } finally {
    await stream.close();
    await lib.terminate();
  }
}
```

## Common mistakes

* Reading `lib.defaultOutputStream` twice and opening one, writing the other
  (`paErrorCodeStreamNotOpened`).
* Treating the returned `int` as a boolean; compare with
  `paErrorCodeNoError`.
* Writing interleaved stereo data as if the frame count were divided by the
  channel count.
* Calling `terminate()` and then trying to play again in the same process.
* Running it on the web or in an isolate-less environment: it needs
  `dart:ffi`, `dart:io` and `Isolate.spawn`.
