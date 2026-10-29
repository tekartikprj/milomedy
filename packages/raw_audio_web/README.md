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
- `example/raw_dart`: Dart.

Serve them with `dart run build_runner serve example:8080`, or, for the plain JS
ones, with any static server, for example
`python3 -m http.server 8080 -d example/raw_worklet_js`. The microphone and the
AudioWorklet need `localhost` or https.
