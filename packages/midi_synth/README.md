# tekartik_midi_synth

MIDI synths in pure Dart (VM, dart2js, dart2wasm), with no asset.

- `MidiSynth`: the interface the engine drives. Channel messages go in
  (`send(status, data1, data2)`, `reset()`), stereo frames come out
  (`render(left, right, start, count)`).
- `DartSynth`: a synth of instruments written in Dart. Each program, and
  optionally the percussion channel, maps to a `DartInstrument`. It handles note
  on and off, volume and expression (a square law), the sustain pedal, all notes
  off, all sound off and reset all controllers.
- Instruments:
  - `ReedInstrument` (from accordelio): accordion reeds read from band-limited
    wave tables. Presets are `treble` (with its registers: clarinet, bassoon,
    piccolo, violin, musette, bandoneon, oboe, master), `bass` and `chord`.
  - `ClickInstrument`: a metronome click, a decaying sine. The accent keys are
    the General MIDI hi wood block and metronome bell.

A SoundFont synth (dart_melty_soundfont) will be a separate package, so an app
that does not use it does not pull it in.

## Setup

```yaml
dependencies:
  tekartik_midi_synth:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/midi_synth
```

## Example

```dart
var synth = DartSynth(sampleRate: 44100, instrument: ReedInstrument.treble());
synth.send(midiNoteOn, 60, 100);
var left = Float32List(4410);
var right = Float32List(4410);
synth.render(left, right, 0, 4410);
synth.send(midiNoteOff, 60);
```
