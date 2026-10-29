import 'package:tekartik_raw_audio/raw_audio.dart';
import 'package:tekartik_raw_audio/raw_audio_memory.dart';
import 'package:test/test.dart';

void main() {
  test('feed', () async {
    final memory = RawAudioManagerMemory();
    var output = memory.createOutput(
      options: RawAudioOutputOptions(sampleRate: 1, channelCount: 1),
    );
    var data = RawAudioData.fromChannelsBytes(
      channelsBytes: [
        Uint8List.fromList([1, 2]),
      ],
    );
    await output.feed(data);
    expect(output.channelsBytes, [
      [1, 2],
    ]);
    data = RawAudioData.fromChannelsBytes(
      channelsBytes: [
        Uint8List.fromList([3, 4, 5]),
      ],
    );
    await output.feed(data);
    expect(output.channelsBytes, [
      [1, 2, 3, 4, 5],
    ]);
  });
}
