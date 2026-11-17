import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fs_shim/fs_memory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/sound_fonts.dart';

/// How a fake location answers.
enum _Answer { file, notFound, other, silent, notSoundFont }

/// A fake web of locations: each url answers as told, ranges included, and
/// every request is recorded.
class _FakeWeb {
  final Uint8List bytes;
  final answers = <String, _Answer>{};
  final requests = <http.BaseRequest>[];

  /// A chunk size small enough for several chunks per file.
  static const chunk = 1000;

  _FakeWeb(this.bytes);

  MockClient get client => MockClient.streaming((request, body) async {
    requests.add(request);
    var answer = answers['${request.url}'] ?? _Answer.notFound;
    switch (answer) {
      case _Answer.notFound:
        return http.StreamedResponse(const Stream.empty(), 404);
      case _Answer.silent:
        // Headers, then nothing.
        return http.StreamedResponse(
          StreamController<List<int>>().stream,
          200,
          contentLength: bytes.length,
        );
      case _Answer.other:
      case _Answer.notSoundFont:
      case _Answer.file:
        var content = switch (answer) {
          _Answer.other => renamedSoundFontBytes('Tiny othr'),
          _Answer.notSoundFont => Uint8List.fromList(
            List.filled(bytes.length, 7),
          ),
          _ => bytes,
        };
        var start = 0;
        var range = request.headers['range'];
        if (range != null) {
          start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
        }
        var rest = content.sublist(start);
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < rest.length; i += chunk)
              rest.sublist(
                i,
                i + chunk > rest.length ? rest.length : i + chunk,
              ),
          ]),
          range == null ? 200 : 206,
          contentLength: rest.length,
          headers: {
            if (range != null)
              'content-range':
                  'bytes $start-${content.length - 1}/${content.length}',
          },
        );
    }
  });
}

void main() {
  var bytes = copySoundFontBytes();
  var hash = sha256.convert(bytes).toString();
  var a = Uri.parse('https://a.example.com/copy.sf2');
  var b = Uri.parse('https://b.example.com/copy.sf2');
  var server = Uri.parse('http://localhost:8095/mirror/');
  var serverFile = Uri.parse(
    'http://localhost:8095/mirror/public/sound_fonts/abc/copy.sf2',
  );

  late _FakeWeb web;
  late MidiSoundFontLibrary library;

  MidiSoundFontSource source({String? sha = '-'}) => MidiSoundFontSource(
    id: 'copy',
    name: 'The copy',
    url: a,
    locations: [b],
    path: 'public/sound_fonts/abc/copy.sf2',
    licence: 'Test only',
    size: bytes.length,
    sha256: sha == '-' ? hash : sha,
  );

  setUp(() {
    web = _FakeWeb(bytes);
    library = MidiSoundFontLibrary(
      fileSystem: newFileSystemMemory(),
      path: 'sf',
      client: web.client,
    );
  });

  test('the candidates: the sound server first, each url once', () {
    expect(source().candidates(), [a, b]);
    expect(source().candidates(soundServer: server), [serverFile, a, b]);
    expect(
      midiSoundServerUri(Uri.parse('http://h:1'), 'x/y.sf2').toString(),
      'http://h:1/x/y.sf2',
    );
  });

  test('the first location answering', () async {
    web.answers['$a'] = _Answer.file;
    var entry = await library.download(source());
    expect(entry.url, '$a');
    expect(await library.read(entry.id), bytes);
    expect(await library.partSize('copy'), 0);
  });

  test('the sound server first, when it has the file', () async {
    web.answers['$serverFile'] = _Answer.file;
    var entry = await library.download(source(), soundServer: server);
    expect(entry.url, '$serverFile');
    expect(web.requests.map((r) => r.url), [serverFile]);
  });

  test('the next location on each kind of failure', () async {
    web.answers
      ..['$serverFile'] = _Answer.notFound
      ..['$a'] = _Answer.other
      ..['$b'] = _Answer.file;
    var entry = await library.download(source(), soundServer: server);
    expect(entry.url, '$b');
    expect(web.requests.map((r) => r.url), [serverFile, a, b]);
  });

  test('none: every attempt reported, nothing added', () async {
    web.answers
      ..['$a'] = _Answer.notSoundFont
      ..['$b'] = _Answer.notFound;
    // No hash to check: the bytes are read as a SoundFont, and refused.
    try {
      await library.download(source(sha: null));
      fail('downloaded');
    } on MidiSoundFontDownloadException catch (e) {
      expect(e.attempts.map((attempt) => attempt.url), [a, b]);
      expect('${e.attempts.last.error}', contains('HTTP 404'));
    }
    expect(await library.list(), hasLength(1));
    expect(await library.partSize('copy'), 0);
  });

  test('a wrong SHA-256 is refused', () async {
    web.answers['$a'] = _Answer.file;
    await expectLater(
      library.download(source(sha: 'beef')),
      throwsA(
        isA<MidiSoundFontDownloadException>().having(
          (e) => '${e.attempts.first.error}',
          'first attempt',
          contains('SHA-256'),
        ),
      ),
    );
  });

  test('silent location: the next after the idle timeout', () async {
    web.answers
      ..['$a'] = _Answer.silent
      ..['$b'] = _Answer.file;
    var entry = await library.download(
      source(),
      idleTimeout: const Duration(milliseconds: 100),
    );
    expect(entry.url, '$b');
  });

  test('cancel keeps the part, the next download resumes it', () async {
    web.answers['$a'] = _Answer.file;
    var cancel = MidiSoundFontDownloadCancel();
    var received = <int>[];
    await expectLater(
      library.download(
        source(),
        cancel: cancel,
        onProgress: (count, total) {
          received.add(count);
          if (count >= 3000) {
            cancel.cancel();
          }
        },
      ),
      throwsA(isA<MidiSoundFontDownloadCancelledException>()),
    );
    var kept = await library.partSize('copy');
    expect(kept, 3000);
    expect(await library.list(), hasLength(1));

    var progress = <int>[];
    var entry = await library.download(
      source(),
      onProgress: (count, total) {
        progress.add(count);
        expect(total, bytes.length);
      },
    );
    // Only the rest was asked for.
    expect(web.requests.last.headers['range'], 'bytes=3000-');
    expect(progress.first, 3000);
    expect(await library.read(entry.id), bytes);
    expect(await library.partSize('copy'), 0);
  });

  test('a part already complete is not downloaded again', () async {
    web.answers['$a'] = _Answer.file;
    var cancel = MidiSoundFontDownloadCancel();
    await expectLater(
      library.download(
        source(),
        cancel: cancel,
        onProgress: (count, total) {
          if (count == bytes.length) {
            cancel.cancel();
          }
        },
      ),
      throwsA(isA<MidiSoundFontDownloadCancelledException>()),
    );
    expect(await library.partSize('copy'), bytes.length);
    var requests = web.requests.length;
    await library.download(source());
    expect(web.requests.length, requests);
  });

  test('ensure: the same SHA-256 imported first, no download', () async {
    var imported = await library.import(bytes);
    expect((await library.sameFile(source()))?.id, imported.id);
    expect((await library.ensure(source())).id, imported.id);
    expect(web.requests, isEmpty);
  });
}
