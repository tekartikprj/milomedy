@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// The worker built by test/setup_sound_font_worker_test.dart (the VM tests
/// first: dart test -p vm, then -p chrome).
const _url = 'sound_font_worker.js';

void main() {
  var sf3 = midiTinySoundFontSf3Bytes();
  late Uint8List expected;

  setUpAll(() async {
    expected = await midiSoundFontDecompress(sf3);
  });

  Future<bool> built() async {
    var response = await web.window.fetch(_url.toJS).toDart;
    if (!response.ok) {
      markTestSkipped('$_url not built: run the VM tests first');
    }
    return response.ok;
  }

  test('decompressed in the worker: the same SF2', () async {
    if (!await built()) {
      return;
    }
    var progress = <(int, int)>[];
    var bytes = Uint8List.fromList(sf3);
    var sf2 = await midiSoundFontWorkerDecompressor(url: _url, fallback: false)(
      bytes,
      onProgress: (done, total) => progress.add((done, total)),
    );
    expect(sf2, expected);
    expect(progress, [(1, 2), (2, 2)]);
    // The bytes given are kept (a copy went to the worker).
    expect(bytes, sf3);
  });

  test('not a valid SF3: a FormatException from the worker', () async {
    if (!await built()) {
      return;
    }
    // The Ogg pages of the samples damaged: their checksums fail.
    var damaged = Uint8List.fromList(sf3);
    for (var i = damaged.length ~/ 3; i < damaged.length * 2 ~/ 3; i++) {
      damaged[i] ^= 0x5a;
    }
    expect(midiSoundFontIsCompressed(damaged), isTrue);
    await expectLater(
      midiSoundFontWorkerDecompressor(url: _url, fallback: false)(damaged),
      throwsFormatException,
    );
  });

  test('an SF2 is returned as is, no worker', () async {
    var sf2 = midiTinySoundFontBytes();
    var decompress = midiSoundFontWorkerDecompressor(
      url: 'missing_worker.js',
      fallback: false,
    );
    expect(identical(await decompress(sf2), sf2), isTrue);
  });

  test('no worker: in the page, or refused', () async {
    var progress = <(int, int)>[];
    var sf2 = await midiSoundFontWorkerDecompressor(url: 'missing_worker.js')(
      sf3,
      onProgress: (done, total) => progress.add((done, total)),
    );
    expect(sf2, expected);
    expect(progress.last, (2, 2));
    await expectLater(
      midiSoundFontWorkerDecompressor(
        url: 'missing_worker.js',
        fallback: false,
      )(sf3),
      throwsA(isA<MidiSoundFontWorkerException>()),
    );
  });

  group('sampler', () {
    test('in the worker: the SoundFont of the samples asked', () async {
      if (!await built()) {
        return;
      }
      var bytes = Uint8List.fromList(sf3);
      var sampler = await midiSoundFontSampler(
        bytes,
        url: _url,
        fallback: false,
      );
      // Moved to the worker: nothing left here but the definition (with
      // dart2wasm, toJS copies them out of the wasm memory: the copy moves).
      if (!const bool.fromEnvironment('dart.tool.dart2wasm')) {
        expect(bytes, isEmpty);
      }
      expect(sampler.definition.name, 'Tiny test SoundFont');
      var local = MidiSoundFontLocalSampler(sf3);
      // Two requests at once, then one with a sample decoded before.
      var both = sampler.soundFont([0, 1]);
      var sine = sampler.soundFont([0]);
      expect(await both, await local.soundFont([0, 1]));
      expect(await sine, await local.soundFont([0]));
      expect(await sampler.soundFont([1]), await local.soundFont([1]));
      // A sample that is not there: the error, then it goes on.
      await expectLater(
        sampler.soundFont([5]),
        throwsA(isA<MidiSoundFontWorkerException>()),
      );
      expect(await sampler.soundFont(const []), await local.soundFont([]));
      await sampler.close();
      await expectLater(sampler.soundFont([0]), throwsStateError);
    });

    test('no worker: in the page, or refused', () async {
      var sampler = await midiSoundFontSampler(
        Uint8List.fromList(sf3),
        url: 'missing_worker.js',
      );
      expect(sampler, isA<MidiSoundFontLocalSampler>());
      expect(
        await sampler.soundFont([0]),
        await MidiSoundFontLocalSampler(sf3).soundFont([0]),
      );
      await expectLater(
        midiSoundFontSampler(
          Uint8List.fromList(sf3),
          url: 'missing_worker.js',
          fallback: false,
        ),
        throwsA(isA<MidiSoundFontWorkerException>()),
      );
    });

    test('not a SoundFont: a FormatException, no worker', () async {
      await expectLater(
        midiSoundFontSampler(Uint8List(64), url: _url),
        throwsFormatException,
      );
    });
  });
}
