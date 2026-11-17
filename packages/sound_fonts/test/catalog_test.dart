import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

void main() {
  /// The catalog as the publish tool of milomedy writes it.
  final published = {
    'version': 1,
    'soundFonts': [
      {
        'id': 'generaluser_gs',
        'name': 'GeneralUser GS',
        'version': '2.0.3',
        'size': 32319396,
        'sha256': midiGeneralUserGsSha256,
        'gitBlobSha1': '298b552d2e9d1307e03e5c5c99d2c046aaed9ec3',
        'presets': 287,
        'licence': 'Free for any use',
        'licencePath': 'public/sound_fonts/9575/LICENSE.txt',
        'path': 'public/sound_fonts/9575/GeneralUser-GS.sf2',
        'locations': ['https://storage.example.com/gu.sf2'],
      },
    ],
  };

  test('read from the published json', () {
    var catalog = MidiSoundFontCatalog.fromJson(published);
    var source = catalog.source(midiGeneralUserGsId)!;
    expect(source.url, Uri.parse('https://storage.example.com/gu.sf2'));
    expect(source.locations, isEmpty);
    expect(source.size, 32319396);
    expect(source.sha256, midiGeneralUserGsSha256);
    expect(source.presetCount, 287);
    expect(source.version, '2.0.3');
    expect(source.licenceUrl, 'public/sound_fonts/9575/LICENSE.txt');
    expect(source.path, 'public/sound_fonts/9575/GeneralUser-GS.sf2');
    expect(catalog.source('nope'), isNull);
  });

  test('round trip', () {
    var catalog = MidiSoundFontCatalog.fromJson(published);
    var again = MidiSoundFontCatalog.fromJson(
      jsonDecode(jsonEncode(catalog.toJson())) as Map<String, Object?>,
    );
    expect(again.toJson(), catalog.toJson());
  });

  test('paths below the base when no location; bad entries skipped', () {
    var catalog = MidiSoundFontCatalog.fromJson({
      'soundFonts': [
        {'id': 'a', 'name': 'A', 'path': 'public/sound_fonts/1/a.sf2'},
        {'id': 'b', 'name': 'B'},
        {
          'id': 3,
          'name': 'C',
          'locations': ['https://x/c.sf2'],
        },
        'nonsense',
      ],
    }, base: Uri.parse('http://localhost:8095'));
    expect(catalog.soundFonts.map((source) => source.id), ['a']);
    expect(
      catalog.soundFonts.single.url,
      Uri.parse('http://localhost:8095/public/sound_fonts/1/a.sf2'),
    );
  });

  test('merge: the newer entry wins, new ones after, the others stay', () {
    MidiSoundFontSource source(String id, String url) =>
        MidiSoundFontSource(id: id, name: id, url: Uri.parse(url), licence: '');
    var builtIn = MidiSoundFontCatalog([
      source('a', 'https://old/a'),
      source('b', 'https://old/b'),
    ]);
    var merged = builtIn.merge(
      MidiSoundFontCatalog([
        source('c', 'https://new/c'),
        source('a', 'https://new/a'),
      ]),
    );
    expect(merged.soundFonts.map((s) => '${s.id} ${s.url}'), [
      'a https://new/a',
      'b https://old/b',
      'c https://new/c',
    ]);
  });

  test('fetch', () async {
    var client = MockClient((request) async {
      if (request.url.path.endsWith('catalog.json')) {
        return http.Response(jsonEncode(published), 200);
      }
      return http.Response('', 404);
    });
    var catalog = await MidiSoundFontCatalog.fetch(
      Uri.parse('https://storage.example.com/catalog.json'),
      client: client,
    );
    expect(catalog.soundFonts.single.id, midiGeneralUserGsId);
    await expectLater(
      MidiSoundFontCatalog.fetch(
        Uri.parse('https://storage.example.com/missing.json'),
        client: client,
      ),
      throwsStateError,
    );
  });
}
