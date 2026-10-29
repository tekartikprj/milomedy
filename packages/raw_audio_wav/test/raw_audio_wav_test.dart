import 'package:tekartik_common_utils/hex_utils.dart';
import 'package:tekartik_raw_audio_wav/raw_audio_wav.dart';
import 'package:test/test.dart';

void main() {
  test('feed', () async {
    final memory = RawAudioManagerWav();
    var output = memory.createOutput(
      options: RawAudioOutputOptions(sampleRate: 1, channelCount: 1),
    );
    var data = RawAudioData.fromChannelsBytes(
      channelsBytes: [
        Uint8List.fromList([1, 2]),
      ],
    );
    await output.feed(data);
    var wav = output.wav;
    var bytes = wav.write();
    // print(hexPretty(bytes));
    // 52 49 46 46  26 00 00 00  57 41 56 45  66 6D 74 20  RIFF &??? WAVE fmt
    // 10 00 00 00  01 00 01 00  01 00 00 00  02 00 00 00  ???? ???? ???? ????
    // 02 00 10 00  64 61 74 61  02 00 00 00  01 02 .. ..  ???? data ???? ??..
    expect(
      bytes,
      parseHexString('''
      52 49 46 46  26 00 00 00  57 41 56 45  66 6D 74 20  
      10 00 00 00  01 00 01 00  01 00 00 00  02 00 00 00
      02 00 10 00  64 61 74 61  02 00 00 00  01 02
    '''),
    );
  });
}
