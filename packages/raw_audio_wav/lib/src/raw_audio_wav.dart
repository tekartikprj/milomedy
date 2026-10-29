import 'dart:typed_data';

import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';
import 'package:tekartik_raw_audio/raw_audio_mixin.dart';
import 'package:wav/bytes_reader.dart';
import 'package:wav/wav.dart';

export 'package:tekartik_raw_audio/raw_audio.dart';

final _memoryManager = RawAudioManagerMemory();

/// Raw audio manager implementation for WAV output.
class RawAudioManagerWav with RawAudioManagerMixin implements RawAudioManager {
  @override
  RawAudioOutputWav createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  }) {
    return RawAudioOutputWav._(
      manager: this,
      feedOptions: feedOptions,
      options: options,
    );
  }
}

/// Raw audio output stream builder for WAV format audio data.
class RawAudioOutputWav with RawAudioOutputMixin implements RawAudioOutput {
  late final RawAudioOutputMemory _outputMemory;
  // ignore: unused_field
  final RawAudioManagerWav _manager;

  /// Converts recorded raw PCM memory samples into a [Wav] instance.
  Wav get wav {
    var sampleCount = _outputMemory.channelsBytes.first.length ~/ 2;
    var channels = _outputMemory.channelsBytes.map((e) {
      var samplesReader = BytesReader(e).getSampleReader(WavFormat.pcm16bit);
      var list = Float64List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        list[i] = samplesReader();
      }
      return list;
    }).toList();

    return Wav(channels, options.sampleRate);
  }

  @override
  RawAudioOutputFeedOptions? get feedOptions => _outputMemory.feedOptions;

  @override
  RawAudioOutputOptions get options => _outputMemory.options;

  RawAudioOutputWav._({
    required this._manager,
    required RawAudioOutputFeedOptions? feedOptions,
    required RawAudioOutputOptions options,
  }) {
    _outputMemory = _memoryManager.createOutput(
      feedOptions: feedOptions,
      options: options,
    );
  }

  @override
  Future<void> feed(RawAudioData data) async {
    await _outputMemory.feed(data);
  }
}
