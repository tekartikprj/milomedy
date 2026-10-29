## Setup

```yaml
  tekartik_raw_audio_web:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/raw_audio_web
```

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
- `example/raw_dart`: Dart.

Serve them with `dart run build_runner serve example:8080`, or, for the plain JS
ones, with any static server, for example
`python3 -m http.server 8080 -d example/raw_worklet_js`. The microphone and the
AudioWorklet need `localhost` or https.
