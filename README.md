# milomedy

Audio output packages for Dart and Flutter: send raw audio to a WAV file, the web,
a phone or the desktop. They are the output layer of a MIDI player in progress;
its engine and synths will be added here.

Status: experimental, the APIs will change.

## Packages

| Package | Path | Content |
|---|---|---|
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
