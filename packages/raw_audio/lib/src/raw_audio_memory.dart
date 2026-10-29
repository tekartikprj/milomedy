import 'package:tekartik_raw_audio/raw_audio.dart';

import 'package:tekartik_raw_audio/raw_audio_mixin.dart';

/// In memory implementation of [RawAudioManager]
class RawAudioManagerMemory
    with RawAudioManagerMixin
    implements RawAudioManager {
  @override
  RawAudioOutputMemory createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  }) {
    return _RawAudioOutputMemory(options: options, feedOptions: feedOptions);
  }
}

/// In memory implementation of [RawAudioOutput]
abstract class RawAudioOutputMemory implements RawAudioOutput {
  /// Channels data
  List<Uint8List> get channelsBytes;
}

/// In memory implementation of [RawAudioOutput]
class _RawAudioOutputMemory
    with RawAudioOutputMixin
    implements RawAudioOutputMemory {
  /// Channels data
  @override
  late final List<Uint8List> channelsBytes;
  @override
  final RawAudioOutputOptions options;
  @override
  final RawAudioOutputFeedOptions? feedOptions;

  /// Creates a [_RawAudioOutputMemory] instance with [options] and optional [feedOptions].
  _RawAudioOutputMemory({required this.options, this.feedOptions}) {
    channelsBytes = List<Uint8List>.generate(
      options.channelCount,
      (index) => Uint8List(0),
    );
  }

  @override
  Future<void> feed(RawAudioData data) async {
    for (var i = 0; i < options.channelCount; i++) {
      channelsBytes[i] = Uint8List.fromList([
        ...channelsBytes[i],
        ...data.channelsBytes[i],
      ]);
    }
  }
}
