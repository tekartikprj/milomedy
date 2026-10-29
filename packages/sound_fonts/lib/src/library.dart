/// The SoundFont library: the SoundFonts downloaded or imported, stored
/// through fs_shim (files on io, IndexedDB on the web) with a JSON index,
/// the default one, and a built-in fallback.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fs_shim/fs_shim.dart';
import 'package:http/http.dart' as http;
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

import 'source.dart';

/// A SoundFont of the library.
class MidiSoundFontEntry {
  /// Its id.
  final String id;

  /// Its name (from its INFO chunk, or given at import).
  final String name;

  /// Its size in bytes.
  final int size;

  /// Its number of presets.
  final int presetCount;

  /// Its copyright notice, where the licence usually is.
  final String copyright;

  /// Its author.
  final String author;

  /// Its comments, where the licence sometimes is.
  final String comments;

  /// The SHA-256 of its bytes (duplicates are refused).
  final String sha256;

  /// Where it was downloaded from, null when imported or built in.
  final String? url;

  /// The licence of its source, null when imported or built in.
  final String? licence;

  /// True for the built-in fallback, always there.
  final bool builtIn;

  /// An entry.
  const MidiSoundFontEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.presetCount,
    required this.sha256,
    this.copyright = '',
    this.author = '',
    this.comments = '',
    this.url,
    this.licence,
    this.builtIn = false,
  });

  factory MidiSoundFontEntry._fromMap(Map<String, Object?> map) =>
      MidiSoundFontEntry(
        id: map['id']! as String,
        name: map['name']! as String,
        size: map['size']! as int,
        presetCount: map['presets']! as int,
        sha256: map['sha256']! as String,
        copyright: map['copyright'] as String? ?? '',
        author: map['author'] as String? ?? '',
        comments: map['comments'] as String? ?? '',
        url: map['url'] as String?,
        licence: map['licence'] as String?,
      );

  Map<String, Object?> _toMap() => {
    'id': id,
    'name': name,
    'size': size,
    'presets': presetCount,
    'sha256': sha256,
    if (copyright.isNotEmpty) 'copyright': copyright,
    if (author.isNotEmpty) 'author': author,
    if (comments.isNotEmpty) 'comments': comments,
    'url': ?url,
    'licence': ?licence,
  };

  @override
  String toString() => 'MidiSoundFontEntry($id, $name, $size bytes)';
}

/// A download that is not the file expected.
class MidiSoundFontDownloadException implements Exception {
  /// What went wrong.
  final String message;

  /// An exception.
  MidiSoundFontDownloadException(this.message);

  @override
  String toString() => 'MidiSoundFontDownloadException: $message';
}

/// The SoundFont library, in [path] of [fileSystem].
class MidiSoundFontLibrary {
  /// The id of the built-in fallback: the tiny SoundFont of
  /// milomedy_midi_synth_sf2 (a sine, a noise), so that something always
  /// plays, offline, with no licence question.
  static const builtInId = 'tiny';

  /// The file system.
  final FileSystem fileSystem;

  /// The folder of the library.
  final String path;

  final http.Client? _client;
  Map<String, Object?>? _index;

  /// A library in [path] of [fileSystem] (`fileSystemDefault` of fs_shim:
  /// files on io, IndexedDB on the web), downloading with [client].
  MidiSoundFontLibrary({
    required this.fileSystem,
    required this.path,
    this._client,
  });

  static final _builtIn = () {
    var bytes = midiTinySoundFontBytes();
    var soundFont = MidiSoundFont.fromBytes(bytes);
    return MidiSoundFontEntry(
      id: builtInId,
      name: soundFont.name,
      size: bytes.length,
      presetCount: soundFont.presets.length,
      sha256: sha256.convert(bytes).toString(),
      builtIn: true,
    );
  }();

  File get _indexFile =>
      fileSystem.file(fileSystem.path.join(path, 'index.json'));

  File _file(String id) =>
      fileSystem.file(fileSystem.path.join(path, '$id.sf2'));

  Future<Map<String, Object?>> _load() async {
    var index = _index;
    if (index != null) {
      return index;
    }
    var file = _indexFile;
    if (await file.exists()) {
      index = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } else {
      index = {'soundFonts': <Object?>[]};
    }
    return _index = index;
  }

  Future<void> _save(Map<String, Object?> index) async {
    await fileSystem.directory(path).create(recursive: true);
    await _indexFile.writeAsString(jsonEncode(index));
  }

  List<MidiSoundFontEntry> _entries(Map<String, Object?> index) => [
    for (var map in (index['soundFonts']! as List).cast<Map>())
      MidiSoundFontEntry._fromMap(map.cast<String, Object?>()),
  ];

  /// The SoundFonts: the built-in one first.
  Future<List<MidiSoundFontEntry>> list() async => [
    _builtIn,
    ..._entries(await _load()),
  ];

  /// The SoundFont [id], null when not in the library.
  Future<MidiSoundFontEntry?> entry(String id) async =>
      (await list()).where((entry) => entry.id == id).firstOrNull;

  /// The bytes of SoundFont [id].
  Future<Uint8List> read(String id) async {
    if (id == builtInId) {
      return midiTinySoundFontBytes();
    }
    if (await entry(id) == null) {
      throw ArgumentError.value(id, 'id', 'not in the library');
    }
    return _file(id).readAsBytes();
  }

  /// The id of the default SoundFont: the one set, or the built-in one.
  Future<String> defaultId() async =>
      (await _load())['default'] as String? ?? builtInId;

  /// Sets the default SoundFont.
  Future<void> setDefault(String id) async {
    if (await entry(id) == null) {
      throw ArgumentError.value(id, 'id', 'not in the library');
    }
    var index = await _load();
    index['default'] = id;
    await _save(index);
  }

  /// Adds the SoundFont [bytes] as [id]: read first (a file that is not a
  /// SoundFont is refused); the same bytes already there are not added
  /// again (the entry there is returned).
  Future<MidiSoundFontEntry> _add(
    Uint8List bytes, {
    required String id,
    String? name,
    MidiSoundFontSource? source,
  }) async {
    var soundFont = MidiSoundFont.fromBytes(bytes);
    var hash = sha256.convert(bytes).toString();
    for (var entry in await list()) {
      if (entry.sha256 == hash) {
        return entry;
      }
    }
    var index = await _load();
    var entries = _entries(index);
    var ids = {builtInId, for (var entry in entries) entry.id};
    var unique = id;
    for (var i = 2; ids.contains(unique); i++) {
      unique = '${id}_$i';
    }
    var entry = MidiSoundFontEntry(
      id: unique,
      name: name ?? soundFont.name,
      size: bytes.length,
      presetCount: soundFont.presets.length,
      sha256: hash,
      copyright: soundFont.copyright,
      author: soundFont.author,
      comments: soundFont.comments,
      url: source?.url.toString(),
      licence: source?.licence,
    );
    await fileSystem.directory(path).create(recursive: true);
    await _file(unique).writeAsBytes(bytes);
    index['soundFonts'] = [
      for (var entry in entries) entry._toMap(),
      entry._toMap(),
    ];
    await _save(index);
    return entry;
  }

  /// Imports the SoundFont [bytes] (a file picked, dropped, fetched), named
  /// [name] (its INFO name by default).
  Future<MidiSoundFontEntry> import(Uint8List bytes, {String? name}) {
    var soundFont = MidiSoundFont.fromBytes(bytes);
    return _add(bytes, id: _slug(name ?? soundFont.name), name: name);
  }

  /// Downloads [source], with [onProgress] (bytes received, total when
  /// known); its size and hash are checked when the source gives them.
  Future<MidiSoundFontEntry> download(
    MidiSoundFontSource source, {
    void Function(int received, int? total)? onProgress,
  }) async {
    var client = _client ?? http.Client();
    try {
      var response = await client.send(http.Request('GET', source.url));
      if (response.statusCode != 200) {
        throw MidiSoundFontDownloadException(
          '${source.url}: HTTP ${response.statusCode}',
        );
      }
      var total = response.contentLength ?? source.size;
      var builder = BytesBuilder(copy: false);
      await for (var chunk in response.stream) {
        builder.add(chunk);
        onProgress?.call(builder.length, total);
      }
      var bytes = builder.takeBytes();
      var size = source.size;
      if (size != null && bytes.length != size) {
        throw MidiSoundFontDownloadException(
          '${source.url}: ${bytes.length} bytes, $size expected',
        );
      }
      var gitBlobSha1 = source.gitBlobSha1;
      if (gitBlobSha1 != null && _gitBlobSha1(bytes) != gitBlobSha1) {
        throw MidiSoundFontDownloadException(
          '${source.url}: not the file expected (git blob $gitBlobSha1)',
        );
      }
      return await _add(
        bytes,
        id: source.id,
        name: source.name,
        source: source,
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// SoundFont [source], downloaded first when not in the library yet: the
  /// default SoundFont on first use.
  Future<MidiSoundFontEntry> ensure(
    MidiSoundFontSource source, {
    void Function(int received, int? total)? onProgress,
  }) async =>
      await entry(source.id) ?? await download(source, onProgress: onProgress);

  /// Deletes SoundFont [id] (not the built-in one); the default goes back
  /// to the built-in one when it was the default.
  Future<void> delete(String id) async {
    if (id == builtInId) {
      throw ArgumentError.value(id, 'id', 'the built-in SoundFont stays');
    }
    var index = await _load();
    var entries = _entries(index);
    if (!entries.any((entry) => entry.id == id)) {
      return;
    }
    index['soundFonts'] = [
      for (var entry in entries)
        if (entry.id != id) entry._toMap(),
    ];
    if (index['default'] == id) {
      index.remove('default');
    }
    await _save(index);
    var file = _file(id);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// The git blob id of [bytes]: the SHA-1 of `blob <size>\0` and the bytes.
String _gitBlobSha1(Uint8List bytes) {
  var digest = _DigestSink();
  sha1.startChunkedConversion(digest)
    ..add(utf8.encode('blob ${bytes.length}\u0000'))
    ..add(bytes)
    ..close();
  return digest.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// An id made of [name]: lower case letters, digits and underscores.
String _slug(String name) {
  var slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'sound_font' : slug;
}
