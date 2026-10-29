# milomedy_midi_audio_stream_example

Plays a metronome and a waltz on accordion reeds through the MIDI engine: a
background isolate feeding `mp_audio_stream` on the desktop, an AudioWorklet on the
web.

- Desktop: `flutter run -d macos` (or `linux`, `windows`).
- Web: build the worklet once with `dart run tool/setup_web_worklet.dart`, then
  run `flutter run -d chrome`.
- On a device: `flutter test integration_test/play_test.dart -d macos`.
