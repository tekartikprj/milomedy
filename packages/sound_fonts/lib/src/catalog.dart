/// The catalog of the SoundFonts an app offers: a JSON file next to them
/// (`catalog.json`), built into the app and refreshed from where it is
/// hosted.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'source.dart';

/// Where the catalog is below a sound server, the layout of the files it
/// lists (`public/sound_fonts/<sha256>/<file>.sf2`).
const midiSoundFontCatalogPath = 'public/sound_fonts/catalog.json';

/// The SoundFonts an app offers, in the order shown.
class MidiSoundFontCatalog {
  /// The catalog version written, the one read.
  static const formatVersion = 1;

  /// The SoundFonts.
  final List<MidiSoundFontSource> soundFonts;

  /// A catalog of [soundFonts].
  const MidiSoundFontCatalog(this.soundFonts);

  /// The catalog of [json] (`{"version": 1, "soundFonts": [...]}`): each
  /// entry gives its `id`, `name`, `licence` and `locations` (the first is
  /// its url), or a `path` resolved below [base] when it has no location;
  /// an entry with neither is skipped, as an entry missing a field or
  /// holding a wrong type (a newer catalog stays readable).
  factory MidiSoundFontCatalog.fromJson(
    Map<String, Object?> json, {
    Uri? base,
  }) {
    var soundFonts = <MidiSoundFontSource>[];
    for (var item in json['soundFonts'] as List? ?? const []) {
      if (item is! Map) {
        continue;
      }
      var source = _sourceOrNull(item.cast<String, Object?>(), base: base);
      if (source != null) {
        soundFonts.add(source);
      }
    }
    return MidiSoundFontCatalog(soundFonts);
  }

  static MidiSoundFontSource? _sourceOrNull(
    Map<String, Object?> map, {
    Uri? base,
  }) {
    try {
      var path = map['path'] as String?;
      var locations = [
        for (var location in map['locations'] as List? ?? const [])
          Uri.parse(location as String),
      ];
      if (locations.isEmpty && path != null && base != null) {
        locations.add(midiSoundServerUri(base, path));
      }
      if (locations.isEmpty) {
        return null;
      }
      return MidiSoundFontSource(
        id: map['id']! as String,
        name: map['name']! as String,
        licence: map['licence'] as String? ?? '',
        url: locations.first,
        locations: locations.skip(1).toList(),
        path: path,
        size: map['size'] as int?,
        sha256: map['sha256'] as String?,
        gitBlobSha1: map['gitBlobSha1'] as String?,
        licenceUrl: (map['licenceUrl'] ?? map['licencePath']) as String?,
        version: map['version'] as String?,
        presetCount: map['presets'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  /// The JSON of this catalog, read back by [MidiSoundFontCatalog.fromJson].
  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'soundFonts': [
      for (var source in soundFonts)
        {
          'id': source.id,
          'name': source.name,
          'version': ?source.version,
          'size': ?source.size,
          'sha256': ?source.sha256,
          'gitBlobSha1': ?source.gitBlobSha1,
          'presets': ?source.presetCount,
          'licence': source.licence,
          'licenceUrl': ?source.licenceUrl,
          'path': ?source.path,
          'locations': [
            for (var url in [source.url, ...source.locations]) '$url',
          ],
        },
    ],
  };

  /// The SoundFont [id], null when not in the catalog.
  MidiSoundFontSource? source(String id) =>
      soundFonts.where((source) => source.id == id).firstOrNull;

  /// This catalog updated by [newer] (the one fetched, over the one built
  /// in): its entries replace those of the same id, its new ones come
  /// after, the entries it does not list stay.
  MidiSoundFontCatalog merge(MidiSoundFontCatalog newer) {
    var ids = {for (var source in soundFonts) source.id};
    return MidiSoundFontCatalog([
      for (var source in soundFonts) newer.source(source.id) ?? source,
      for (var source in newer.soundFonts)
        if (!ids.contains(source.id)) source,
    ]);
  }

  /// The catalog at [url] (an http error or a body that is not a catalog
  /// throws), its paths resolved below [base] (the sound server it comes
  /// from, when it lists no location).
  static Future<MidiSoundFontCatalog> fetch(
    Uri url, {
    http.Client? client,
    Uri? base,
  }) async {
    var owned = client == null;
    var httpClient = client ?? http.Client();
    try {
      var response = await httpClient.get(url);
      if (response.statusCode != 200) {
        throw StateError('$url: HTTP ${response.statusCode}');
      }
      var json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) {
        throw FormatException('$url: not a catalog');
      }
      return MidiSoundFontCatalog.fromJson(
        json.cast<String, Object?>(),
        base: base,
      );
    } finally {
      if (owned) {
        httpClient.close();
      }
    }
  }

  @override
  String toString() =>
      'MidiSoundFontCatalog(${soundFonts.map((source) => source.id)})';
}
