import 'package:milomedy_midi_asset/midi_asset.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:test/test.dart';

void main() {
  group('songs', () {
    test('twenty, in shape', () {
      expect(midiAssetSongs, hasLength(20));
      expect(midiAssetSongs.where((song) => song.pianoOnly), hasLength(5));
      expect({for (var song in midiAssetSongs) song.id}, hasLength(20));
      for (var asset in midiAssetSongs) {
        var song = MidiSong.fromBytes(asset.toBytes());
        expect(song.notes.length, greaterThan(150), reason: asset.id);
        expect(song.duration, inInclusiveRange(20, 75), reason: asset.id);
        expect(song.trackNames.first, asset.title);
        var programs = song.initialPrograms;
        if (asset.pianoOnly) {
          expect(programs, {0: 0}, reason: asset.id);
        } else {
          // Drums on the percussion channel, at least three instruments.
          expect(song.channels, contains(9), reason: asset.id);
          expect(programs.length, greaterThanOrEqualTo(4), reason: asset.id);
        }
      }
      expect(midiAssetSong('jazz_swing')?.title, 'Jazz Swing');
      expect(midiAssetSong('nope'), isNull);
      expect(
        midiAssetSong('march')!.flutterAsset,
        'packages/milomedy_midi_asset/midi/march.mid',
      );
    });

    test('the same bytes each time, on every platform', () {
      var sum = 0;
      for (var asset in midiAssetSongs) {
        var bytes = asset.toBytes();
        expect(asset.toBytes(), bytes, reason: asset.id);
        for (var byte in bytes) {
          sum = (sum * 31 + byte) % 1000003;
        }
      }
      expect(sum, _checksum);
    });
  });

  test('chords', () {
    var chord = MidiChord.parse('F#m7b5');
    expect(chord.root, 6);
    expect(chord.intervals, [0, 3, 6, 10]);
    expect(chord.isMinor, isTrue);
    expect(MidiChord.parse('Bb').root, 10);
    expect(MidiChord.parse('C').voicing(60), [60, 64, 67]);
    expect(MidiChord.parse('G7').bass(), 43);
    expect(MidiChord.parse('Am').tones(60, 72), [60, 64, 69, 72]);
    expect(() => MidiChord.parse('H7'), throwsFormatException);
    expect(() => MidiChord.parse('Cxyz'), throwsFormatException);
  });

  test('random: the same everywhere', () {
    var random = MidiAssetRandom(1);
    expect([for (var i = 0; i < 5; i++) random.nextInt(100)], _randomFirst);
  });
}

/// The checksum of the bytes of the songs, the same on the VM and the web.
const _checksum = 135721;

/// The first values of the random generator from 1.
const _randomFirst = [49, 49, 5, 44, 83];
