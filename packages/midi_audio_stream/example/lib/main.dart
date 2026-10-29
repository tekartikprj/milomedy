import 'dart:async';

import 'package:flutter/material.dart';
import 'package:milomedy_midi_audio_stream/midi_audio_stream.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';

import 'src/songs.dart';

void main() => runApp(const ExampleApp());

/// The example app.
class ExampleApp extends StatelessWidget {
  /// The app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MIDI engine',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const PlayerScreen(),
  );
}

/// The player screen.
class PlayerScreen extends StatefulWidget {
  /// The screen.
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Created at the first tap (the web needs a user gesture).
  Future<MidiHostPlayer>? _player;
  MidiHostPlayer? _ready;
  Timer? _timer;
  var _metronome = false;
  var _bpm = 100.0;
  var _speed = 1.0;
  var _transpose = 0;
  String? _error;

  Future<MidiHostPlayer> get _get => _player ??= () async {
    try {
      var player = await midiCreatePlayer(synths: exampleSynths);
      player.onError.listen((message) => setState(() => _error = message));
      player.onState.listen((_) => setState(() {}));
      _timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => setState(() {}),
      );
      return _ready = player;
    } catch (e) {
      setState(() => _error = '$e');
      rethrow;
    }
  }();

  double get _effectiveSpeed =>
      _speed * (_metronome ? _bpm / exampleBaseBpm : 1);

  Future<void> _load(MidiTimeline timeline, {required bool metronome}) async {
    var player = await _get;
    _metronome = metronome;
    player
      ..load(timeline)
      ..setLoop(metronome ? timeline.start : null, timeline.end)
      ..speed = _effectiveSpeed
      ..transpose = _transpose;
    await player.play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ready?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var player = _ready;
    return Scaffold(
      appBar: AppBar(title: const Text('MIDI engine')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _load(exampleMetronome(), metronome: true),
                child: const Text('Metronome'),
              ),
              FilledButton(
                onPressed: () => _load(exampleWaltz(), metronome: false),
                child: const Text('Waltz'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.play_arrow),
                onPressed: player == null ? null : () => player.play(),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.pause),
                onPressed: player?.pause,
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.stop),
                onPressed: player?.stop,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            player == null
                ? 'Tap Metronome or Waltz'
                : '${player.state.name} '
                      '${player.position.toStringAsFixed(1)} s',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Text('Metronome tempo: ${_bpm.round()} bpm'),
          Slider(
            value: _bpm,
            min: 40,
            max: 240,
            onChanged: (value) {
              setState(() => _bpm = value);
              player?.speed = _effectiveSpeed;
            },
          ),
          Text('Speed: ${_speed.toStringAsFixed(2)}'),
          Slider(
            value: _speed,
            min: 0.25,
            max: 2,
            onChanged: (value) {
              setState(() => _speed = value);
              player?.speed = _effectiveSpeed;
            },
          ),
          Text('Transpose: $_transpose'),
          Slider(
            value: _transpose.toDouble(),
            min: -12,
            max: 12,
            divisions: 24,
            onChanged: (value) {
              setState(() => _transpose = value.round());
              player?.transpose = _transpose;
            },
          ),
        ],
      ),
    );
  }
}
