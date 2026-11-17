import 'dart:async';
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:test/test.dart';

/// A host elsewhere: the commands and their buffers to move, recorded.
class _RecordingPlayer extends MidiHostPlayer {
  final sent = <(Map<String, Object?>, List<ByteBuffer>?)>[];

  _RecordingPlayer() : super(trackCount: 1);

  void _answer(Map<String, Object?> command) {
    if (command['type'] == MidiHostCommands.sync) {
      scheduleMicrotask(
        () => handleEvent({'type': MidiHostEvents.sync, 'id': command['id']}),
      );
    }
  }

  @override
  void sendCommand(Map<String, Object?> command) {
    sent.add((command, null));
    _answer(command);
  }

  @override
  void sendCommandTransfer(
    Map<String, Object?> command,
    List<ByteBuffer> transfer,
  ) {
    sent.add((command, transfer));
    _answer(command);
  }

  @override
  double get clock => 0;
}

/// A host in the same isolate: nothing to move.
class _LocalPlayer extends MidiHostPlayer {
  final sent = <Map<String, Object?>>[];

  _LocalPlayer() : super(trackCount: 1);

  @override
  void sendCommand(Map<String, Object?> command) {
    sent.add(command);
    if (command['type'] == MidiHostCommands.sync) {
      scheduleMicrotask(
        () => handleEvent({'type': MidiHostEvents.sync, 'id': command['id']}),
      );
    }
  }

  @override
  double get clock => 0;
}

void main() {
  (Map<String, Object?>, List<ByteBuffer>?) soundFontCommand(
    _RecordingPlayer player,
  ) => player.sent.firstWhere(
    (sent) => sent.$1['type'] == MidiHostCommands.soundFont,
  );

  test('loadSoundFont: the buffer moved only when asked', () async {
    var player = _RecordingPlayer();
    var bytes = Uint8List.fromList([1, 2, 3]);
    await player.loadSoundFont('sf', bytes);
    expect(soundFontCommand(player).$2, isNull);

    player.sent.clear();
    await player.loadSoundFont('sf', bytes, transfer: true);
    var (command, transfer) = soundFontCommand(player);
    expect(identical(command['bytes'], bytes), isTrue);
    expect(transfer!.single, bytes.buffer);
  });

  test('loadSoundFont: a view on part of a buffer, copied first', () async {
    var player = _RecordingPlayer();
    var buffer = Uint8List.fromList([0, 1, 2, 3, 4]);
    var view = Uint8List.sublistView(buffer, 1, 4);
    await player.loadSoundFont('sf', view, transfer: true);
    var (command, transfer) = soundFontCommand(player);
    var sent = command['bytes']! as Uint8List;
    expect(sent, [1, 2, 3]);
    expect(sent.buffer == buffer.buffer, isFalse);
    expect(transfer!.single, sent.buffer);
  });

  test('loadSoundFont: nothing to move, sent as any command', () async {
    var player = _LocalPlayer();
    var bytes = Uint8List.fromList([1, 2, 3]);
    await player.loadSoundFont('sf', bytes, transfer: true);
    expect(
      player.sent.where((sent) => sent['type'] == MidiHostCommands.soundFont),
      hasLength(1),
    );
    expect(bytes, [1, 2, 3]);
  });
}
