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
  `getDeviceInfo` (an index out of range, `-1` when there is no default
  output device) and `getInfo` throw `StateError` on failure.
* Sequence: `var lib = await getPortAudioLib(); await lib.initialize();`,
  `var stream = lib.defaultOutputStream;` (every getter access creates a new
  unopened stream object: keep the reference), `await stream.open(parameters:
  PortAudioOutputStreamParameters(numChannels: 1, sampleRate: 44100,
  framesPerBuffer: 2048))`, `await stream.start()`, repeated
  `await stream.writeDoubles(samples)`, `await stream.stop()` (waits for the
  pending audio), `await stream.close()`, and finally `await lib.terminate()`.
* `terminate()` also ends the worker isolate (aborting still-open streams
  first). Call it once when the program is done: until then the worker keeps
  the program alive (it does not exit), and afterwards the singleton cannot
  be re-initialized in the same process (`getPortAudioLib()` returns the
  same instance and its calls never complete).
* Samples: `writeDoubles(List<double>)` takes float32 values in -1.0..1.0 and
  completes once PortAudio consumed them. With `numChannels > 1` the samples
  are interleaved (left, right, left...): the frame count passed to
  PortAudio is the list length divided by the channel count (a last
  incomplete frame is dropped). Write chunks of about `framesPerBuffer`
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
  runners (`platformIo.runningOnGithub`): they have no sound card, and the system
  PortAudio aborts there since the 2026-10 ubuntu-24.04 images. `example/`
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
  var channels = wav.channels;
  var numChannels = channels.length;
  var frameCount = channels.first.length;

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
        numChannels: numChannels,
        sampleRate: wav.samplesPerSecond.toDouble(),
        framesPerBuffer: chunk,
      ),
    );
    await stream.start();
    for (var i = 0; i < frameCount; i += chunk) {
      var end = i + chunk > frameCount ? frameCount : i + chunk;
      var available = await stream.getWriteAvailable();
      stdout.write('\r$available frames free, sending ${end - i}   ');
      // Interleaved: one sample per channel for each frame.
      await stream.writeDoubles([
        for (var frame = i; frame < end; frame++)
          for (var channel in channels) channel[frame],
      ]);
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
* Writing the channels one after the other (all the left samples, then the
  right ones) instead of interleaved.
* Calling `terminate()` and then trying to play again in the same process,
  or forgetting it (the program never exits).
* Asking `getDeviceInfo` of `getDefaultOutputDevice()` without checking it
  is not negative (no output device): a `StateError`.
* Running it on the web or in an isolate-less environment: it needs
  `dart:ffi`, `dart:io` and `Isolate.spawn`.
