import 'dart:typed_data';

import 'package:tekartik_common_utils/num_utils.dart';

export 'dart:typed_data' show Uint8List;

/// Raw audio data
abstract class RawAudioData {
  /// Get the frame count
  int get frameCount;

  /// Get sub frames
  RawAudioData subFrames(int start, int end);

  /// Create raw audio data from channels bytes
  factory RawAudioData.fromChannelsBytes({
    required List<Uint8List> channelsBytes,
  }) {
    return _RawAudioDataChannelsBytes(channelsBytes: channelsBytes);
  }

  /// Not always optimized
  List<Uint8List> get channelsBytes;

  /// Create raw audio data from int16 list
  factory RawAudioData.fromInt16List(List<int> data) {
    var bytes = Uint8List(data.length * 2);
    var byteData = bytes.buffer.asByteData();
    for (var i = 0; i < data.length; i++) {
      byteData.setInt16(i * 2, data[i]);
    }
    return RawAudioData.fromChannelsBytes(channelsBytes: [bytes]);
  }
}

class _RawAudioDataChannelsBytes implements RawAudioData {
  @override
  int get frameCount => channelsBytes.first.length ~/ 2;
  @override
  final List<Uint8List> channelsBytes;

  _RawAudioDataChannelsBytes({required this.channelsBytes});

  @override
  RawAudioData subFrames(int start, int end) {
    end = end.boundedMax(frameCount);
    var startBytes = start * 2.boundedMin(0);
    var endBytes = (end * 2).boundedMax(frameCount * 2);

    return RawAudioData.fromChannelsBytes(
      channelsBytes: channelsBytes
          .map((bytes) => bytes.sublist(startBytes, endBytes))
          .toList(),
    );
  }
}

/// Raw audio data manager
abstract class RawAudioManager {
  /// Create a new raw audio data output
  RawAudioOutput createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  });
}

/// Default sample rate
const int rawAudioSampleRateDefault = 44100;

/// Default channel count
const int rawAudioChannelCountDefault = 2;

/// Callback on feed
typedef RawAudioOnFeedCallback =
    void Function(RawAudioOutput output, int frameCount);

/// Output feed options
class RawAudioOutputFeedOptions {
  /// Frame count threshold
  final int feedThreshold;

  /// Callback on feed
  final RawAudioOnFeedCallback onFeed;

  /// Creates a [RawAudioOutputFeedOptions] instance with [feedThreshold] and [onFeed] callback.
  RawAudioOutputFeedOptions({
    required this.feedThreshold,
    required this.onFeed,
  });
}

/// Only supported audio format
enum RawAudioFormFormat {
  /// 16 bits per sample signed
  pcm16,
}

/// Output options
class RawAudioOutputOptions {
  /// Sample rate (default to 44100)
  final int sampleRate;

  /// Channel count (default to 2)
  final int channelCount;

  /// Format
  final RawAudioFormFormat format;

  /// Creates a [RawAudioOutputOptions] instance with optional [sampleRate], [channelCount], and [format].
  RawAudioOutputOptions({
    this.sampleRate = rawAudioSampleRateDefault,
    this.channelCount = rawAudioChannelCountDefault,
    this.format = RawAudioFormFormat.pcm16,
  });

  @override
  String toString() =>
      'RawAudioOutputOptions(sampleRate: $sampleRate, channelCount: $channelCount)';
}

/// Output
abstract class RawAudioOutput {
  /// Get the options
  RawAudioOutputOptions get options;

  /// Get the feed options
  RawAudioOutputFeedOptions? get feedOptions;

  /// Feed raw audio data
  Future<void> feed(RawAudioData data);

  /// Start play
  Future<void> play();

  /// Stop play
  Future<void> stop();
}

/// Default mixin
mixin RawAudioManagerMixin implements RawAudioManager {
  @override
  RawAudioOutput createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  }) {
    throw UnimplementedError('RawAudioManager.createOutput');
  }
}

/// Default mixin
mixin RawAudioOutputMixin implements RawAudioOutput {
  @override
  RawAudioOutputOptions get options =>
      throw UnimplementedError('RawAudioOutput.options');

  @override
  RawAudioOutputFeedOptions? get feedOptions =>
      throw UnimplementedError('RawAudioOutput.feedOptions');

  @override
  Future<void> feed(RawAudioData data) {
    throw UnimplementedError('RawAudioOutput.feed');
  }

  @override
  Future<void> play() async {
    // Do nothing by default
    // throw UnimplementedError('RawAudioOutput.play');
  }
  @override
  Future<void> stop() async {
    // Do nothing by default
    // throw UnimplementedError('RawAudioOutput.stop');
  }
}
