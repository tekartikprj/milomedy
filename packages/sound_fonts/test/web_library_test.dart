@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fs_shim/fs_browser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/sound_fonts.dart';

void main() {
  test('kept in IndexedDB', () async {
    var fileSystem = newFileSystemWeb(name: 'milomedy_sound_fonts_test');
    var library = MidiSoundFontLibrary(fileSystem: fileSystem, path: 'sf');
    var copy = copySoundFontBytes();
    var entry = await library.import(copy);
    await library.setDefault(entry.id);
    // Another library on the same database.
    var again = MidiSoundFontLibrary(
      fileSystem: newFileSystemWeb(name: 'milomedy_sound_fonts_test'),
      path: 'sf',
    );
    expect(await again.defaultId(), entry.id);
    expect(await again.read(entry.id), copy);
    await again.delete(entry.id);
    expect(await again.list(), hasLength(1));
  });

  test('a download cancelled then resumed, in IndexedDB', () async {
    var bytes = copySoundFontBytes();
    var ranges = <String?>[];
    var client = MockClient.streaming((request, body) async {
      var range = request.headers['range'];
      ranges.add(range);
      var start = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
      var rest = Uint8List.sublistView(bytes, start);
      return http.StreamedResponse(
        Stream.fromIterable([
          for (var i = 0; i < rest.length; i += 1000)
            rest.sublist(i, i + 1000 > rest.length ? rest.length : i + 1000),
        ]),
        range == null ? 200 : 206,
        contentLength: rest.length,
      );
    });
    var fileSystem = newFileSystemWeb(name: 'milomedy_sound_fonts_resume');
    var library = MidiSoundFontLibrary(
      fileSystem: fileSystem,
      path: 'sf',
      client: client,
    );
    var source = MidiSoundFontSource(
      id: 'copy',
      name: 'The copy',
      url: Uri.parse('https://example.com/copy.sf2'),
      licence: 'Test only',
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    var cancel = MidiSoundFontDownloadCancel();
    await expectLater(
      library.download(
        source,
        cancel: cancel,
        onProgress: (received, total) {
          if (received >= 4000) {
            cancel.cancel();
          }
        },
      ),
      throwsA(isA<MidiSoundFontDownloadCancelledException>()),
    );
    expect(await library.partSize('copy'), 4000);
    var entry = await library.download(source);
    expect(ranges, [null, 'bytes=4000-']);
    expect(await library.read(entry.id), bytes);
    await library.delete(entry.id);
  });
}
