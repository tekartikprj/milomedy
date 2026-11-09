# tekartik_raw_audio_web

Web Audio experiments: raw audio played and captured in a browser, with
plain JS and with Dart (`package:web`). Examples only, there is no library to
depend on: for a raw audio output API see `tekartik_raw_audio` and its
backends in this repository.

## Examples

The microphone, heard 2 seconds later:

- `example/raw_js`: plain JS, through a ScriptProcessorNode (deprecated, kept as
  the reference).
- `example/raw_worklet_js`: plain JS, through an AudioWorklet. `processor.js` runs
  on the audio thread, copies its input to its output, and posts the input level
  to the page through its port. Press Start: the AudioContext needs a user
  gesture.
- `example/raw_worklet_dart`: the same as `raw_worklet_js`, the page and the
  processor written in Dart. Only JS can declare a class extending
  AudioWorkletProcessor, but `registerProcessor` only needs a constructor whose
  prototype has `process`. In `processor.dart`, a Dart function builds the
  processor with `Reflect.construct`, so its dart2js output is the worklet module
  as it is. Build it first with `dart run tool/build_raw_worklet_dart.dart`, into
  `processor.js` (git-ignored). build_runner's development compiler cannot make a
  worklet module.

Played from Dart:

- `example/raw_dart`: a C major scale made in Dart, played whole ("play 3s")
  or streamed as chunks, one AudioBufferSourceNode each ("play 60s"), from a
  test menu.

Serve them with `dart run build_runner serve example:8080`, or, for the plain JS
ones, with any static server, for example
`python3 -m http.server 8080 -d example/raw_worklet_js`. The microphone and the
AudioWorklet need `localhost` or https.
