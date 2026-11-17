# milomedy_midi_synth

MIDI synths in pure Dart (VM, dart2js, dart2wasm), with no asset.

- `MidiSynth`: the interface the engine drives. Channel messages go in
  (`send(status, data1, data2)`, `reset()`), stereo frames come out
  (`render(left, right, start, count)`).
- `DartSynth`: a synth of instruments written in Dart. Each program, and
  optionally the percussion channel, maps to a `DartInstrument`. It handles note
  on and off, volume and expression (a square law), the sustain pedal, all notes
  off, all sound off and reset all controllers. It takes the tuning of each
  channel, the fine tuning (RPN 1) and the coarse tuning (RPN 2), and gives it to
  its next notes; reset all controllers resets it, as dart_melty_soundfont does.
- `DartTunableInstrument`: an instrument whose voices take the tuning of their
  channel in cents (a frequency factor of 2^(cents / 1200)). The reeds and the
  click are; another `DartInstrument` plays in tune.
- Instruments:
  - `ReedInstrument` (from accordelio): accordion reeds read from band-limited
    wave tables. Presets are `treble` (with its registers: clarinet, bassoon,
    piccolo, violin, musette, bandoneon, oboe, master), `bass` and `chord`.
  - `ClickInstrument`: a metronome click, a decaying sine. The accent keys are
    the General MIDI hi wood block and metronome bell.
- The MIDI numbers: messages, controllers (data entry, RPN, reverb and chorus
  sends...), the RPNs, `midiFineTuningValue(cents)` and `midiFineTuningCents`,
  `midiKeyFrequency`, the General MIDI program names.

The SoundFont synth (dart_melty_soundfont) is a separate package,
`milomedy_midi_synth_sf2`, so an app that does not use it does not pull it in.

## Setup

```yaml
dependencies:
  milomedy_midi_synth:
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

Tune a channel 7.85 cents up (A4 at 442 Hz), as the engine does with
`tuneCents`:

```dart
var value = midiFineTuningValue(7.85); // 8835, 8192 in tune
synth
  ..send(midiControlChange, midiControllerRpnMsb, 0)
  ..send(midiControlChange, midiControllerRpnLsb, midiRpnFineTuning)
  ..send(midiControlChange, midiControllerDataEntry, value >> 7)
  ..send(midiControlChange, midiControllerDataEntryLsb, value & 0x7f)
  ..send(midiControlChange, midiControllerRpnMsb, 127) // the null RPN
  ..send(midiControlChange, midiControllerRpnLsb, 127)
  ..send(midiNoteOn, 69, 100); // 442 Hz
```
