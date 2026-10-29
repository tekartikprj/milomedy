/// The isolate player (io): the engine runs in a background isolate, which
/// opens its audio stream there (mp_audio_stream, through
/// `milomedy_midi_audio_stream`) and feeds it from a timer. A slow frame of
/// the UI isolate is never an audio gap.
library;

import 'dart:async';
import 'dart:isolate';

import 'midi_engine.dart';

/// Opens the output stream at a sample rate, in the player's isolate.
typedef MidiPcmStreamOpener = MidiPcmStream Function(int sampleRate);

/// What the isolate is started with.
class _Setup {
  final SendPort events;
  final List<Map<String, Object?>> synths;
  final MidiPcmStreamOpener openStream;
  final int sampleRate;
  final double latency;

  _Setup(
    this.events,
    this.synths,
    this.openStream,
    this.sampleRate,
    this.latency,
  );
}

const _close = 'close';
const _closed = 'closed';

/// A player whose engine runs in a background isolate, pushing its frames
/// [latency] ahead on a raw stream.
class MidiIsolatePlayer extends MidiHostPlayer {
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _events;
  final _clock = Stopwatch()..start();
  Completer<void>? _closing;

  MidiIsolatePlayer._(
    this._isolate,
    this._commands,
    this._events,
    int trackCount,
  ) : super(trackCount: trackCount);

  /// A player of one track per synth of [synths], at [sampleRate], its
  /// output opened by [openStream] in the player's isolate, its frames pushed
  /// [latency] seconds ahead.
  ///
  /// [openStream] is sent to the isolate: a top-level function, or a closure
  /// that captures only sendable values (a closure keeps every variable of
  /// the function that creates it).
  static Future<MidiIsolatePlayer> spawn({
    required List<MidiSynthSpec> synths,
    required MidiPcmStreamOpener openStream,
    int sampleRate = 44100,
    double latency = 0.1,
  }) async {
    var events = ReceivePort();
    var ready = Completer<SendPort>();
    MidiIsolatePlayer? player;
    events.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is Map) {
        if (message['type'] == _closed) {
          player?._closing?.complete();
        } else if (player != null) {
          player.handleEvent(message);
        } else if (!ready.isCompleted) {
          // The stream could not be opened.
          ready.completeError(StateError('${message['message']}'));
        }
      }
    });
    Isolate isolate;
    SendPort commands;
    try {
      isolate = await Isolate.spawn(
        _main,
        _Setup(
          events.sendPort,
          [for (var spec in synths) spec.toMap()],
          openStream,
          sampleRate,
          latency,
        ),
        debugName: 'midi_engine',
      );
      commands = await ready.future;
    } catch (_) {
      events.close();
      rethrow;
    }
    return player = MidiIsolatePlayer._(
      isolate,
      commands,
      events,
      synths.length,
    );
  }

  @override
  void sendCommand(Map<String, Object?> command) => _commands.send(command);

  /// The isolate reports the position heard when it sends it.
  @override
  double get clock => _clock.elapsedMicroseconds / 1e6;

  @override
  Future<void> close() async {
    var closing = _closing = Completer<void>();
    _commands.send({'type': _close});
    await closing.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _isolate.kill(),
    );
    _events.close();
    await super.close();
  }
}

/// The isolate: opens the stream, feeds it every 5 ms, handles the commands.
void _main(_Setup setup) {
  MidiPcmStream stream;
  try {
    stream = setup.openStream(setup.sampleRate);
  } catch (e) {
    setup.events.send({'type': MidiHostEvents.error, 'message': '$e'});
    return;
  }
  var host = MidiStreamHost(
    stream: stream,
    sampleRate: setup.sampleRate,
    synths: [for (var map in setup.synths) MidiSynthSpec.fromMap(map)],
    latency: setup.latency,
    send: setup.events.send,
  );
  var commands = ReceivePort();
  host.feed();
  var timer = Timer.periodic(
    const Duration(milliseconds: 5),
    (_) => host.feed(),
  );
  commands.listen((message) {
    if (message is! Map) {
      return;
    }
    if (message['type'] == _close) {
      timer.cancel();
      stream.close();
      commands.close();
      Isolate.exit(setup.events, {'type': _closed});
    }
    host.handle(message);
  });
  setup.events.send(commands.sendPort);
}
