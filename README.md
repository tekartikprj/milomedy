# milomedy

The packages of a MIDI player in progress, for Dart and Flutter: a MIDI engine and
synths in pure Dart, and audio outputs (a WAV file, the web, a phone, the desktop).

Status: experimental, the APIs will change.

## Packages

| Package | Path | Content |
|---|---|---|
| `milomedy_midi_engine` | `packages/midi_engine` | Plays a timeline of MIDI events on the audio clock: seek, loop, speed, transpose, one synth per track, a mixer, a player, a stream output and a Web Audio output, offline rendering to WAV, a metronome |
| `milomedy_midi_audio_stream` | `packages/midi_audio_stream` | Flutter: the engine on `mp_audio_stream` in a background isolate (Android, iOS, Linux, macOS, Windows), and `midiCreatePlayer`, which picks the AudioWorklet player on the web |
| `milomedy_midi_synth` | `packages/midi_synth` | The `MidiSynth` interface and instruments written in Dart, with no asset: accordion reeds, a metronome click |
| `tekartik_raw_audio` | `packages/raw_audio` | Raw audio output interface (16-bit PCM, feed callback), memory output, test tone generator |
| `tekartik_raw_audio_wav` | `packages/raw_audio_wav` | Output to a WAV file |
| `tekartik_raw_audio_web` | `packages/raw_audio_web` | Web Audio examples (no library yet) |
| `tekartik_raw_audio_pcm_sound` | `packages/raw_audio_pcm_sound` | Output through `flutter_pcm_sound` (Android, iOS, macOS) |
| `tekartik_port_audio` | `packages/port_audio` | PortAudio bindings (FFI), with a worker isolate |
| `tekartik_libao` | `packages/libao` | libao bindings (FFI) |

## Setup

The packages are not on pub.dev. Use them from git:

```yaml
dependencies:
  tekartik_raw_audio:
    git:
      url: https://github.com/tekartikprj/milomedy
      path: packages/raw_audio
```

`tekartik_port_audio` and `tekartik_libao` need the PortAudio or libao library
installed on the system; see their READMEs.

## Licence

MIT, see [LICENSE](LICENSE). `packages/libao` is derived from
[tiagohm/libao](https://github.com/tiagohm/libao) (MIT, see its own `LICENSE`).
The PortAudio and libao libraries are not included.
