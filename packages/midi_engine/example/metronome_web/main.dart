import 'dart:js_interop';

import 'package:tekartik_midi_engine/midi_engine.dart';
import 'package:tekartik_midi_engine/web_audio.dart';
import 'package:web/web.dart' as web;

/// The tempo the timeline is built at: the tempo set is a speed, so that a
/// change keeps the place in the measure.
const _baseBpm = 60.0;

final _bpmInput = web.document.querySelector('#bpm') as web.HTMLInputElement;
final _beatsInput =
    web.document.querySelector('#beats') as web.HTMLInputElement;
final _button = web.document.querySelector('#play') as web.HTMLButtonElement;
final _beat = web.document.querySelector('#beat') as web.HTMLElement;

MidiPlayer? _player;

/// A metronome on Web Audio: clicks rendered in Dart, no asset.
void main() {
  _button.onclick = ((web.Event _) {
    _toggle();
  }).toJS;
  _bpmInput.onchange = ((web.Event _) {
    _player?.speed = _bpm / _baseBpm;
  }).toJS;
  _beatsInput.onchange = ((web.Event _) {
    var player = _player;
    if (player != null) {
      var playing = player.isPlaying;
      _load(player);
      if (playing) {
        player.play();
      }
    }
  }).toJS;
  web.document.onvisibilitychange = ((web.Event _) {
    // The timers of a hidden page are slowed down: render further ahead.
    _player?.lookahead = web.document.hidden ? 1.5 : 0.25;
  }).toJS;
  web.window.requestAnimationFrame(_showBeat.toJS);
}

double get _bpm => (double.tryParse(_bpmInput.value) ?? 100).clamp(20, 300);

int get _beats => (int.tryParse(_beatsInput.value) ?? 4).clamp(1, 12);

void _load(MidiPlayer player) {
  var timeline = midiMetronomeTimeline(bpm: _baseBpm, beats: _beats);
  player
    ..load(timeline)
    ..setLoop(timeline.start, timeline.end)
    ..speed = _bpm / _baseBpm;
}

Future<void> _toggle() async {
  var player = _player;
  if (player == null) {
    var sink = MidiWebAudioSink();
    player = _player = MidiPlayer(
      sink,
      midiMetronomeEngine(sampleRate: sink.sampleRate),
    );
    _load(player);
  }
  if (player.isPlaying) {
    player.stop();
    _button.textContent = 'Start';
  } else {
    await player.play();
    _button.textContent = 'Stop';
  }
}

void _showBeat(JSNumber _) {
  var player = _player;
  _beat.textContent = player != null && player.isPlaying
      // A beat is a second of the timeline.
      ? '${(player.position % _beats).floor() + 1}'
      : '';
  web.window.requestAnimationFrame(_showBeat.toJS);
}
