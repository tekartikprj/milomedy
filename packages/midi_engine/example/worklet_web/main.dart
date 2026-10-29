import 'dart:js_interop';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_engine/web_worklet.dart';
import 'package:web/web.dart' as web;

/// The tempo the metronome is built at: the tempo set is a speed.
const _baseBpm = 60.0;

T _element<T extends JSObject>(String id) =>
    web.document.querySelector('#$id') as T;

final _bpm = _element<web.HTMLInputElement>('bpm');
final _file = _element<web.HTMLInputElement>('file');
final _speed = _element<web.HTMLInputElement>('speed');
final _transpose = _element<web.HTMLInputElement>('transpose');
final _position = _element<web.HTMLElement>('position');
final _status = _element<web.HTMLElement>('status');

/// The player, created at the first click (an AudioContext needs a user
/// gesture).
Future<MidiWorkletPlayer>? _player;

/// True when the metronome is loaded (its tempo is a speed).
var _metronome = false;

/// One track: the reed for every program, the click for the percussion.
Future<MidiWorkletPlayer> get _ready => _player ??= () async {
  var player = await MidiWorkletPlayer.create(
    synths: [
      const MidiSynthSpec(
        instrument: MidiInstrumentIds.reed,
        percussion: MidiInstrumentIds.click,
      ),
    ],
  );
  player.onError.listen((message) => _status.textContent = message);
  return player;
}();

void _onClick(String id, Future<void> Function(MidiWorkletPlayer) action) {
  _element<web.HTMLElement>(id).onclick = (web.Event _) {
    _ready.then(action);
  }.toJS;
}

double get _speedValue =>
    (double.tryParse(_speed.value) ?? 1).clamp(0.25, 2) *
    (_metronome
        ? (double.tryParse(_bpm.value) ?? 100).clamp(20, 300) / _baseBpm
        : 1);

void main() {
  _onClick('metronome', (player) async {
    _metronome = true;
    var timeline = midiMetronomeTimeline(bpm: _baseBpm);
    player
      ..load(timeline)
      ..setLoop(timeline.start, timeline.end)
      ..speed = _speedValue;
    await player.play();
  });
  _onClick('play', (player) => player.play());
  _onClick('pause', (player) async => player.pause());
  _onClick('stop', (player) async => player.stop());
  _file.onchange = (web.Event _) {
    var file = _file.files?.item(0);
    if (file != null) {
      _loadFile(file);
    }
  }.toJS;
  for (var input in [_bpm, _speed]) {
    input.onchange = (web.Event _) {
      _player?.then((player) => player.speed = _speedValue);
    }.toJS;
  }
  _transpose.onchange = (web.Event _) {
    _player?.then(
      (player) => player.transpose = int.tryParse(_transpose.value) ?? 0,
    );
  }.toJS;
  web.window.requestAnimationFrame(_showPosition.toJS);
}

Future<void> _loadFile(web.File file) async {
  var player = await _ready;
  try {
    var bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    var song = MidiSong.fromBytes(bytes);
    _metronome = false;
    player
      ..load(song.toTimeline())
      ..setLoop(null, null)
      ..speed = _speedValue;
    _status.textContent =
        '${file.name}: ${song.notes.length} notes, '
        '${song.duration.toStringAsFixed(1)} s';
    await player.play();
  } catch (e) {
    _status.textContent = '${file.name}: $e';
  }
}

void _showPosition(JSNumber _) {
  _player?.then((player) {
    _position.textContent = '${player.position.toStringAsFixed(1)} s';
  });
  web.window.requestAnimationFrame(_showPosition.toJS);
}
