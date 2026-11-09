import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekartik_raw_audio_pcm_sound/raw_audio_pcm_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The buffers sent to the platform.
  var fed = <List<int>>[];
  setUp(() {
    fed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_pcm_sound/methods'),
          (call) async {
            if (call.method == 'feed') {
              fed.add((call.arguments as Map)['buffer'] as List<int>);
            }
            return null;
          },
        );
  });

  test('a view is fed alone, not its whole buffer', () async {
    var output = rawAudioManagerPcmSound.createOutput(
      options: RawAudioOutputOptions(sampleRate: 8000, channelCount: 1),
    );
    // A long render fed chunk by chunk.
    var rendered = Uint8List.fromList(List.generate(16, (i) => i));
    for (var start = 0; start < 16; start += 8) {
      await output.feed(
        RawAudioData.fromChannelsBytes(
          channelsBytes: [Uint8List.sublistView(rendered, start, start + 8)],
        ),
      );
    }
    expect(fed, [
      [0, 1, 2, 3, 4, 5, 6, 7],
      [8, 9, 10, 11, 12, 13, 14, 15],
    ]);
  });
}
