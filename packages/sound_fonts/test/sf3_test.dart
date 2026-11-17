import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fs_shim/fs_memory.dart' show newFileSystemMemory;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

/// The tiny test SoundFont in SF3.
Uint8List tinySf3() => midiTinySoundFontSf3Bytes();

void main() {
  var sf2 = midiTinySoundFontBytes();

  group('sf3', () {
    test('recognized', () {
      expect(midiSoundFontIsCompressed(tinySf3()), isTrue);
      expect(midiSoundFontIsCompressed(sf2), isFalse);
      expect(midiSoundFontIsCompressed(Uint8List.fromList([1, 2, 3])), isFalse);
    });

    test('decompressed: the SF2 it stands for', () async {
      var progress = <(int, int)>[];
      var back = await midiSoundFontDecompress(
        tinySf3(),
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(progress, [(1, 2), (2, 2)]);
      expect(midiSoundFontIsCompressed(back), isFalse);
      // The same samples: lengths, loops, rates, types.
      expect(midiSoundFontSampleDifferences(sf2, back), isEmpty);
      var soundFont = MidiSoundFont.fromBytes(back);
      expect(soundFont.name, 'Tiny test SoundFont');
      expect(soundFont.presets, hasLength(2));
      // Close to the originals: the sine, the noise.
      var snr = midiSoundFontSampleSnr(sf2, back);
      expect(snr, hasLength(2));
      expect(snr.first, greaterThan(20));
      expect(snr.last, greaterThan(3));
      // The sine sounds as before.
      var original = _render(sf2);
      var decoded = _render(back);
      var noise = 0.0;
      var signal = 0.0;
      for (var i = 0; i < original.length; i++) {
        signal += original[i] * original[i];
        noise += (original[i] - decoded[i]) * (original[i] - decoded[i]);
      }
      expect(signal, greaterThan(0));
      expect(noise / signal, lessThan(0.05));
    });

    test('an SF2 stays as is', () async {
      expect(identical(await midiSoundFontDecompress(sf2), sf2), isTrue);
      expect(midiSoundFontSampleDifferences(sf2, sf2), isEmpty);
    });

    test('compressing an SF3 is refused', () {
      expect(
        midiSoundFontCompress(
          tinySf3(),
          encode: (frames, rate) async => Uint8List(0),
        ),
        throwsFormatException,
      );
    });

    test(
      'compressed by an encoder: offsets, relative loops, the flag',
      () async {
        // A fake encoder: the frames as bytes (not decodable, the layout only).
        var sf3 = await midiSoundFontCompress(
          sf2,
          encode: (frames, rate) async => Uint8List.fromList(
            frames.buffer.asUint8List(
              frames.offsetInBytes,
              frames.lengthInBytes,
            ),
          ),
        );
        expect(midiSoundFontIsCompressed(sf3), isTrue);
        expect(sf3.length, lessThan(sf2.length));
      },
    );
  });

  group('library', () {
    late MidiSoundFontLibrary library;

    setUp(() {
      library = MidiSoundFontLibrary(
        fileSystem: newFileSystemMemory(),
        path: 'sf',
      );
    });

    test('import: kept as SF2, once', () async {
      var bytes = tinySf3();
      var unpacked = <(int, int)>[];
      var entry = await library.import(
        bytes,
        onUnpack: (done, total) => unpacked.add((done, total)),
      );
      expect(unpacked.last, (2, 2));
      expect(entry.originalSha256, sha256.convert(bytes).toString());
      expect(entry.presetCount, 2);
      var stored = await library.read(entry.id);
      expect(midiSoundFontIsCompressed(stored), isFalse);
      expect(entry.sha256, sha256.convert(stored).toString());
      expect(entry.size, stored.length);

      // Again: the entry there, nothing decoded.
      unpacked.clear();
      var again = await library.import(
        bytes,
        onUnpack: (done, total) => unpacked.add((done, total)),
      );
      expect(again.id, entry.id);
      expect(unpacked, isEmpty);
      expect(await library.list(), hasLength(2));
    });

    test('download: checked as SF3, kept as SF2, found again', () async {
      var bytes = tinySf3();
      var url = Uri.parse('https://example.com/tiny.sf3');
      var source = MidiSoundFontSource(
        id: 'tiny_sf3',
        name: 'Tiny SF3',
        url: url,
        licence: 'test',
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        compressed: true,
      );
      var library = MidiSoundFontLibrary(
        fileSystem: newFileSystemMemory(),
        path: 'sf',
        client: MockClient(
          (request) async => request.url == url
              ? http.Response.bytes(bytes, 200)
              : http.Response('', 404),
        ),
      );
      var unpacked = 0;
      var entry = await library.download(
        source,
        onUnpack: (done, total) => unpacked = done,
      );
      expect(unpacked, 2);
      expect(entry.id, 'tiny_sf3');
      expect(entry.url, '$url');
      expect(entry.originalSha256, source.sha256);
      expect(
        midiSoundFontIsCompressed(await library.read('tiny_sf3')),
        isFalse,
      );
      expect((await library.sameFile(source))?.id, 'tiny_sf3');
      expect((await library.ensure(source)).id, 'tiny_sf3');
    });
  });

  group('catalog', () {
    var json = {
      'version': 1,
      'soundFonts': [
        {
          'id': 'gu',
          'name': 'GeneralUser GS',
          'licence': 'free',
          'locations': ['https://example.com/gu.sf2'],
        },
      ],
      'compressedSoundFonts': [
        {
          'id': 'gu_sf3',
          'name': 'GeneralUser GS',
          'licence': 'free',
          'size': 9110502,
          'locations': ['https://example.com/gu.sf3'],
        },
      ],
    };

    test('the SF3 apart, first', () {
      var catalog = MidiSoundFontCatalog.fromJson(json);
      expect(catalog.soundFonts.map((source) => source.id), ['gu_sf3', 'gu']);
      expect(catalog.source('gu_sf3')!.compressed, isTrue);
      expect(catalog.source('gu')!.compressed, isFalse);
      // Written back in their lists: an older app reads soundFonts only.
      var written = catalog.toJson();
      expect(
        (written['soundFonts']! as List).map((item) => (item as Map)['id']),
        ['gu'],
      );
      expect(
        (written['compressedSoundFonts']! as List).map(
          (item) => (item as Map)['id'],
        ),
        ['gu_sf3'],
      );
      expect(
        MidiSoundFontCatalog.fromJson(
          written,
        ).soundFonts.map((source) => (source.id, source.compressed)),
        [('gu_sf3', true), ('gu', false)],
      );
    });

    test('GeneralUser GS in SF3', () {
      var source = midiGeneralUserGsSf3(
        url: Uri.parse('https://example.com/gu.sf3'),
      );
      expect(source.compressed, isTrue);
      expect(source.sha256, midiGeneralUserGsSf3Sha256);
      expect(source.id, isNot(midiGeneralUserGsId));
      expect(source.sameAs, midiGeneralUserGsId);
      expect(
        midiGeneralUserGs(url: Uri.parse('https://example.com/gu.sf2')).sameAs,
        midiGeneralUserGsSf3Id,
      );
      var catalog = MidiSoundFontCatalog([source]);
      expect(
        MidiSoundFontCatalog.fromJson(
          catalog.toJson(),
        ).soundFonts.single.sameAs,
        midiGeneralUserGsId,
      );
    });
  });
}

/// One second of A4 on the sine of [bytes], mono.
Float32List _render(Uint8List bytes) {
  var synth = MidiSoundFontSynth(
    MidiSoundFont.fromBytes(bytes),
    reverbAndChorus: false,
  );
  synth.send(0x90, 69, 100);
  var left = Float32List(44100);
  var right = Float32List(44100);
  synth.render(left, right, 0, left.length);
  return left;
}
