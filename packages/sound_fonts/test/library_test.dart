import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/sound_fonts.dart';

void main() {
  late FileSystem fileSystem;
  late MidiSoundFontLibrary library;
  var copy = copySoundFontBytes();

  setUp(() {
    fileSystem = newFileSystemMemory();
    library = MidiSoundFontLibrary(fileSystem: fileSystem, path: 'sf');
  });

  test('empty: the built-in fallback, the default', () async {
    var entries = await library.list();
    expect(entries.single.id, MidiSoundFontLibrary.builtInId);
    expect(entries.single.builtIn, isTrue);
    expect(entries.single.presetCount, 2);
    expect(await library.defaultId(), MidiSoundFontLibrary.builtInId);
    expect(await library.read('tiny'), midiTinySoundFontBytes());
    expect(() => library.read('nope'), throwsArgumentError);
  });

  test('import: read, refused when not a SoundFont, no duplicate', () async {
    var entry = await library.import(copy);
    expect(entry.id, 'tiny_copy_soundfont');
    expect(entry.name, 'Tiny copy SoundFont');
    expect((entry.size, entry.presetCount), (copy.length, 2));
    expect(await library.read(entry.id), copy);
    // The same bytes: the entry there.
    expect((await library.import(copy, name: 'Again')).id, entry.id);
    // The built-in bytes are there already.
    expect(
      (await library.import(midiTinySoundFontBytes())).id,
      MidiSoundFontLibrary.builtInId,
    );
    expect(() => library.import(Uint8List(100)), throwsA(anything));
    expect((await library.list()).map((entry) => entry.id), [
      'tiny',
      'tiny_copy_soundfont',
    ]);
    // Kept: a new library on the same files finds it.
    var again = MidiSoundFontLibrary(fileSystem: fileSystem, path: 'sf');
    expect((await again.entry(entry.id))?.name, 'Tiny copy SoundFont');
  });

  test('ids stay unique', () async {
    var entry = await library.import(copy, name: 'Tiny');
    expect(entry.id, 'tiny_2');
    expect(entry.name, 'Tiny');
  });

  test('the default, delete', () async {
    var entry = await library.import(copy);
    await library.setDefault(entry.id);
    expect(await library.defaultId(), entry.id);
    expect(() => library.setDefault('nope'), throwsArgumentError);
    expect(() => library.delete('tiny'), throwsArgumentError);
    await library.delete(entry.id);
    expect(await library.entry(entry.id), isNull);
    expect(await library.defaultId(), 'tiny');
    expect(await fileSystem.file('sf/${entry.id}.sf2').exists(), isFalse);
  });

  group('download', () {
    /// A client serving [bytes] in chunks of 1000, counting its requests.
    var requests = 0;
    MockClient client(Uint8List bytes, {int status = 200}) {
      requests = 0;
      return MockClient.streaming((request, body) async {
        requests++;
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += 1000)
              bytes.sublist(
                i,
                i + 1000 > bytes.length ? bytes.length : i + 1000,
              ),
          ]),
          status,
          contentLength: bytes.length,
        );
      });
    }

    MidiSoundFontSource source({int? size, String? sha1}) =>
        MidiSoundFontSource(
          id: 'copy',
          name: 'The copy',
          url: Uri.parse('https://example.com/copy.sf2'),
          licence: 'Test only',
          size: size,
          gitBlobSha1: sha1,
        );

    MidiSoundFontLibrary libraryWith(MockClient client) => MidiSoundFontLibrary(
      fileSystem: fileSystem,
      path: 'sf',
      client: client,
    );

    test('checked, with its progress', () async {
      var library = libraryWith(client(copy));
      var progress = <(int, int?)>[];
      var entry = await library.download(
        source(size: copy.length, sha1: gitBlobSha1(copy)),
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(entry.id, 'copy');
      expect(entry.name, 'The copy');
      expect(entry.url, 'https://example.com/copy.sf2');
      expect(entry.licence, 'Test only');
      expect(await library.read('copy'), copy);
      expect(progress.first, (1000, copy.length));
      expect(progress.last, (copy.length, copy.length));
    });

    test('not the file expected: nothing added', () async {
      var library = libraryWith(client(copy));
      await expectLater(
        library.download(source(size: copy.length + 1)),
        throwsA(isA<MidiSoundFontDownloadException>()),
      );
      await expectLater(
        library.download(source(sha1: '0' * 40)),
        throwsA(isA<MidiSoundFontDownloadException>()),
      );
      await expectLater(
        libraryWith(client(copy, status: 404)).download(source()),
        throwsA(isA<MidiSoundFontDownloadException>()),
      );
      expect(await library.list(), hasLength(1));
    });

    test('ensure: downloaded on first use only', () async {
      var library = libraryWith(client(copy));
      await library.ensure(source());
      expect(requests, 1);
      expect((await library.ensure(source())).id, 'copy');
      expect(requests, 1);
    });
  });

  test('GeneralUser GS, from the url given', () {
    var url = Uri.parse('https://example.com/GeneralUser-GS.sf2');
    var source = midiGeneralUserGs(url: url);
    expect(source.id, midiGeneralUserGsId);
    expect(source.url, url);
    expect(source.size, 32319396);
    expect(source.gitBlobSha1, hasLength(40));
    expect(
      midiGeneralUserGsUpstreamUrl.path,
      endsWith('/97049183643d5fc5a9322a69c5b09efb667c6c3a/GeneralUser-GS.sf2'),
    );
  });
}
