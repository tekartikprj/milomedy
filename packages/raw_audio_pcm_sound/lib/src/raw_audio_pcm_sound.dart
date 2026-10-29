import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:tekartik_common_utils/byte_data_utils.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_mixin.dart';

/// Using flutter_pcm_sound
abstract class RawAudioManagerPcmSound
    with RawAudioManagerMixin
    implements RawAudioManager {
  /// Default constructor
  factory RawAudioManagerPcmSound._() => _RawAudioManagerPcmSound();
  @override
  RawAudioOutputPcmSound createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  });

  /// Stop playing globally
  Future<void> stopAll();
}

/// Global manager
final RawAudioManagerPcmSound rawAudioManagerPcmSound =
    RawAudioManagerPcmSound._();

class _RawAudioManagerPcmSound implements RawAudioManagerPcmSound {
  @override
  RawAudioOutputPcmSound createOutput({
    required RawAudioOutputOptions options,
    RawAudioOutputFeedOptions? feedOptions,
  }) {
    return _RawAudioOutputPcmSound(
      this,
      options: options,
      feedOptions: feedOptions,
    );
  }

  /// Stop playing globally
  @override
  Future<void> stopAll() async {
    await _stop();
  }

  Future<void> _stop() async {
    await _lock.synchronized(() async {
      if (_playing) {
        _playing = false;
        //await FlutterPcmSound.stop();
      }
    });
  }

  final _lock = Lock();
  var _playing = false;
  _RawAudioOutputPcmSound? _current;
  Future<void> _play() async {
    await _lock.synchronized(() async {
      if (!_playing) {
        _playing = true;
        // await FlutterPcmSound.play();
      }
    });
  }
}

/// raw audio output pcm sound
abstract class RawAudioOutputPcmSound implements RawAudioOutput {
  /// Start play
  @override
  Future<void> play();

  /// Stop play
  @override
  Future<void> stop();
}

class _RawAudioOutputPcmSound
    with RawAudioOutputMixin
    implements RawAudioOutputPcmSound {
  // ignore: unused_field
  final _RawAudioManagerPcmSound _manager;
  @override
  final RawAudioOutputOptions options;

  @override
  Future<void> play() async {
    await _ready;
  }

  @override
  Future<void> stop() async {
    await _manager._stop();
  }

  @override
  final RawAudioOutputFeedOptions? feedOptions;

  _RawAudioOutputPcmSound(
    _RawAudioManagerPcmSound manager, {
    required this.options,
    required this.feedOptions,
  }) : _manager = manager;

  static final _initLock = Lock();

  late final _ready = () async {
    await _initLock.synchronized(() async {
      var existing = _manager._current;
      if (existing != null) {
        if (options.sampleRate != existing.options.sampleRate ||
            options.channelCount != existing.options.channelCount) {
          throw UnsupportedError(
            'Only one instance of RawAudioOutputPcmSound is supported with the same sampleRate/channelCount',
          );
        }
      } else {
        await FlutterPcmSound.setup(
          sampleRate: options.sampleRate,
          channelCount: options.channelCount,
        );
      }
      if (feedOptions != null) {
        await FlutterPcmSound.setFeedThreshold(feedOptions!.feedThreshold);
        FlutterPcmSound.setFeedCallback((remainingFrames) {
          feedOptions!.onFeed(this, remainingFrames);
        });
      }
      await _manager._stop();
      await _manager._play();
      _manager._current = this;
    });
  }();

  @override
  Future<void> feed(RawAudioData data) async {
    await _ready;
    var bytes = data.channelsBytes.first;

    await FlutterPcmSound.feed(
      PcmArrayInt16(bytes: byteDataFromUint8List(bytes)),
    );
  }
}
