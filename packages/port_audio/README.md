# tekartik_port_audio

Play PCM audio from the Dart VM (command line, server, desktop without
Flutter) through the [PortAudio](https://www.portaudio.com/) C library:
float samples written to the default output device. Every call runs in a
worker isolate that owns the native handles, so the blocking writes never
freeze your isolate.

Dart VM only (`dart:ffi`, `dart:io`, isolates): Linux, macOS, Windows. Not
for the web; in Flutter use an audio plugin instead.

## Getting started

1. The native library:
   - Linux: `sudo apt-get install portaudio19-dev` (`libportaudio.so`).
   - macOS: [MacPorts](https://www.macports.org/),
     `sudo port install portaudio` (`/opt/local/lib/libportaudio.dylib`;
     elsewhere, e.g. Homebrew, pass its path to `getPortAudioLib(path:)`).
   - Windows: `libportaudio64bit.dll` is downloaded on first use from
     github.com/spatialaudio/portaudio-binaries into `.local/lib/` of the
     current folder (network needed), or pass a path.
2. A git dependency (not on pub.dev):

   ```yaml
   dependencies:
     tekartik_port_audio:
       git:
         url: https://github.com/tekartikprj/milomedy
         path: packages/port_audio
   ```

3. Play one second of a 440 Hz tone:

   ```dart
   import 'dart:math';

   import 'package:tekartik_port_audio/port_audio.dart';

   Future<void> main() async {
     const sampleRate = 44100;
     const frames = 2048;
     var lib = await getPortAudioLib();
     if (await lib.initialize() != paErrorCodeNoError) {
       throw StateError('PortAudio initialize failed');
     }
     // Keep the reference: each access creates another stream.
     var stream = lib.defaultOutputStream;
     try {
       await stream.open(
         parameters: PortAudioOutputStreamParameters(
           numChannels: 1,
           sampleRate: sampleRate.toDouble(),
           framesPerBuffer: frames,
         ),
       );
       await stream.start();
       var buffer = List<double>.filled(frames, 0);
       for (var frame = 0; frame < sampleRate;) {
         for (var i = 0; i < frames; i++, frame++) {
           buffer[i] = 0.3 * sin(2 * pi * 440 * frame / sampleRate);
         }
         await stream.writeDoubles(buffer);
       }
       await stream.stop();
     } finally {
       await stream.close();
       // Once, at the end: the program cannot exit before.
       await lib.terminate();
     }
   }
   ```

More in [example/](example): `example_3s_small_chunks.dart` streams a
stereo WAV file (`example_sound.dart` writes it to `.local/` first),
`native_example*.dart` use the synchronous native bindings directly.

## Good to know

- Errors are return codes, C style: compare with `paErrorCodeNoError` (0);
  negative values are PortAudio `PaErrorCode`s,
  `paErrorCodeOutputUnderflowed` (-9980) on a write is harmless, and the
  package adds `paErrorCodeStreamNotOpened`, `paErrorCodeStreamAlreadyOpened`
  and `paErrorCodeInvalidStream`. `getDeviceInfo` (a device that does not
  exist) and `getInfo` (a stream not opened) throw a `StateError`.
- `writeDoubles` takes samples from -1 to 1, interleaved when there are
  several channels (left, right, left...); write about `framesPerBuffer`
  frames at a time, each call copies the list to the worker.
- `terminate()` ends the worker isolate: call it once, when done. Before it
  the program does not exit; after it the library cannot be used again in
  the same process (the calls never complete).
- `debugPortAudio = true` before `initialize()` logs every native call.
- Tests (`dart test`, VM only) need a sound device; they are skipped on
  GitHub runners.
