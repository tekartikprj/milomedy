/// The SoundFont library: the SoundFonts downloaded or imported, stored
/// through fs_shim (files on io, IndexedDB on the web) with a JSON index,
/// the default one, and a built-in fallback. An SF3 (compressed samples) is
/// stored as the SF2 it stands for, turned once when added, or kept as it
/// is (`keepCompressed`), played per song.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fs_shim/fs_shim.dart';
import 'package:http/http.dart' as http;
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

import 'definition.dart';
import 'sf3.dart';
import 'source.dart';
import 'worker/decompressor.dart';

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

  /// The SHA-256 of the file it was made from, when that was an SF3 (its
  /// bytes are the SF2 the SF3 stands for); null otherwise.
  final String? originalSha256;

  /// Where it was downloaded from, null when imported or built in.
  final String? url;

  /// The licence of its source, null when imported or built in.
  final String? licence;

  /// True for the built-in fallback, always there.
  final bool builtIn;

  /// True for an SF3 kept as it is (`keepCompressed`): its bytes are the
  /// SF3, played per song (`MidiSoundFontSampler`), not loaded whole.
  final bool compressed;

  /// An entry.
  const MidiSoundFontEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.presetCount,
    required this.sha256,
    this.originalSha256,
    this.copyright = '',
    this.author = '',
    this.comments = '',
    this.url,
    this.licence,
    this.builtIn = false,
    this.compressed = false,
  });

  factory MidiSoundFontEntry._fromMap(Map<String, Object?> map) =>
      MidiSoundFontEntry(
        id: map['id']! as String,
        name: map['name']! as String,
        size: map['size']! as int,
        presetCount: map['presets']! as int,
        sha256: map['sha256']! as String,
        originalSha256: map['originalSha256'] as String?,
        copyright: map['copyright'] as String? ?? '',
        author: map['author'] as String? ?? '',
        comments: map['comments'] as String? ?? '',
        url: map['url'] as String?,
        licence: map['licence'] as String?,
        compressed: map['compressed'] as bool? ?? false,
      );

  Map<String, Object?> _toMap() => {
    'id': id,
    'name': name,
    'size': size,
    'presets': presetCount,
    'sha256': sha256,
    'originalSha256': ?originalSha256,
    if (copyright.isNotEmpty) 'copyright': copyright,
    if (author.isNotEmpty) 'author': author,
    if (comments.isNotEmpty) 'comments': comments,
    'url': ?url,
    'licence': ?licence,
    if (compressed) 'compressed': true,
  };

  @override
  String toString() => 'MidiSoundFontEntry($id, $name, $size bytes)';
}

/// A location tried by a download, and why it gave no SoundFont.
class MidiSoundFontDownloadAttempt {
  /// The url tried.
  final Uri url;

  /// What went wrong there.
  final Object error;

  /// An attempt.
  const MidiSoundFontDownloadAttempt(this.url, this.error);

  @override
  String toString() => '$url: $error';
}

/// A download that gave no SoundFont: not the file expected, or no
/// location answering.
class MidiSoundFontDownloadException implements Exception {
  /// What went wrong.
  final String message;

  /// The locations tried, in order, and why each failed.
  final List<MidiSoundFontDownloadAttempt> attempts;

  /// An exception.
  MidiSoundFontDownloadException(this.message, {this.attempts = const []});

  @override
  String toString() => [
    'MidiSoundFontDownloadException: $message',
    for (var attempt in attempts) '  $attempt',
  ].join('\n');
}

/// Stops a download ([MidiSoundFontLibrary.download]): what was received
/// is kept, the next download of the same SoundFont resumes it.
class MidiSoundFontDownloadCancel {
  var _cancelled = false;

  /// True once [cancel] called.
  bool get isCancelled => _cancelled;

  /// Stops the download at its next chunk.
  void cancel() => _cancelled = true;
}

/// A download stopped by [MidiSoundFontDownloadCancel.cancel].
class MidiSoundFontDownloadCancelledException implements Exception {
  /// The SoundFont whose download stopped.
  final String id;

  /// The bytes received and kept (resumed next time).
  final int received;

  /// An exception.
  MidiSoundFontDownloadCancelledException(this.id, this.received);

  @override
  String toString() =>
      'MidiSoundFontDownloadCancelledException: $id ($received bytes kept)';
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

  /// Turns an SF3 into its SF2 (on import and download).
  final MidiSoundFontDecompressor _decompress;

  /// True to keep an SF3 downloaded or imported as it is (9 MB instead of
  /// 32 for GeneralUser GS, no unpacking): its entry is
  /// [MidiSoundFontEntry.compressed], played per song by a
  /// `MidiSoundFontSampler`. False to turn it into the SF2 it stands for,
  /// loaded whole (the apps before).
  final bool keepCompressed;

  // No future is kept once complete: one complete calls back through the
  // zone it was made in, a library used in two zones (the real and the fake
  // async ones of a widget test) would wait for the other one.

  /// The index, once read.
  Map<String, Object?>? _index;

  /// The first read of the index, while it runs.
  Future<Map<String, Object?>>? _reading;

  /// The last change, while it runs: the index is read, changed and written
  /// back across awaits, changes run one after the other.
  Future<void>? _lastChange;

  /// A library in [path] of [fileSystem] (`fileSystemDefault` of fs_shim:
  /// files on io, IndexedDB on the web), downloading with [client]; an SF3
  /// turned into its SF2 by [decompress] (`midiSoundFontDecompress` here by
  /// default, `midiSoundFontWorkerDecompressor()` in a web worker), unless
  /// [keepCompressed].
  MidiSoundFontLibrary({
    required this.fileSystem,
    required this.path,
    this._client,
    MidiSoundFontDecompressor? decompress,
    this.keepCompressed = false,
  }) : _decompress = decompress ?? midiSoundFontDecompress;

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

  File _file(String id, {bool compressed = false}) => fileSystem.file(
    fileSystem.path.join(path, compressed ? '$id.sf3' : '$id.sf2'),
  );

  /// The index, read once (two first reads at once share it, a failed read
  /// is tried again next time).
  Future<Map<String, Object?>> _load() async {
    var index = _index;
    if (index != null) {
      return index;
    }
    var reading = _reading ??= _readIndex();
    try {
      return _index ??= await reading;
    } finally {
      if (identical(_reading, reading)) {
        _reading = null;
      }
    }
  }

  Future<Map<String, Object?>> _readIndex() async {
    var file = _indexFile;
    if (await file.exists()) {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    }
    return {'soundFonts': <Object?>[]};
  }

  /// Runs [change] after the changes started before it.
  Future<T> _change<T>(Future<T> Function() change) async {
    var previous = _lastChange;
    // Sync: the next change, waiting, goes on in its own zone at once.
    var done = Completer<void>.sync();
    _lastChange = done.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await change();
    } finally {
      if (identical(_lastChange, done.future)) {
        _lastChange = null;
      }
      done.complete();
    }
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

  /// The bytes of SoundFont [id]: an SF2, or the SF3 of a
  /// [MidiSoundFontEntry.compressed] one.
  Future<Uint8List> read(String id) async {
    if (id == builtInId) {
      return midiTinySoundFontBytes();
    }
    var found = await entry(id);
    if (found == null) {
      throw ArgumentError.value(id, 'id', 'not in the library');
    }
    return _file(id, compressed: found.compressed).readAsBytes();
  }

  /// The presets of SoundFont [id], by bank then program: its definition
  /// read, not its samples (an SF3 is not decoded).
  Future<List<MidiSoundFontPreset>> presets(String id) async =>
      MidiSoundFontDefinition.fromBytes(await read(id)).presets;

  /// The id of the default SoundFont: the one set, or the built-in one.
  Future<String> defaultId() async =>
      (await _load())['default'] as String? ?? builtInId;

  /// Sets the default SoundFont.
  Future<void> setDefault(String id) => _change(() async {
    if (await entry(id) == null) {
      throw ArgumentError.value(id, 'id', 'not in the library');
    }
    var index = await _load();
    index['default'] = id;
    await _save(index);
  });

  /// Adds the SoundFont [bytes] (an SF2) as [id]: read first (a file that
  /// is not a SoundFont is refused); the same bytes already there are not
  /// added again (the entry there is returned). [originalSha256]: the SF3
  /// they were made from.
  Future<MidiSoundFontEntry> _add(
    Uint8List bytes, {
    required String id,
    String? name,
    MidiSoundFontSource? source,
    Uri? url,
    String? originalSha256,
    bool compressed = false,
  }) => _change(
    () => _addNow(
      bytes,
      id: id,
      name: name,
      source: source,
      url: url,
      originalSha256: originalSha256,
      compressed: compressed,
    ),
  );

  Future<MidiSoundFontEntry> _addNow(
    Uint8List bytes, {
    required String id,
    String? name,
    MidiSoundFontSource? source,
    Uri? url,
    String? originalSha256,
    required bool compressed,
  }) async {
    // An SF3 kept: its definition read (its samples decode when played).
    var soundFont = compressed
        ? _Info.ofDefinition(MidiSoundFontDefinition.fromBytes(bytes))
        : _Info.ofSoundFont(MidiSoundFont.fromBytes(bytes));
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
      presetCount: soundFont.presetCount,
      sha256: hash,
      originalSha256: originalSha256,
      copyright: soundFont.copyright,
      author: soundFont.author,
      comments: soundFont.comments,
      url: (url ?? source?.url)?.toString(),
      licence: source?.licence,
      compressed: compressed,
    );
    await fileSystem.directory(path).create(recursive: true);
    await _file(unique, compressed: compressed).writeAsBytes(bytes);
    index['soundFonts'] = [
      for (var entry in entries) entry._toMap(),
      entry._toMap(),
    ];
    await _save(index);
    return entry;
  }

  /// Imports the SoundFont [bytes] (a file picked, dropped, fetched), named
  /// [name] (its INFO name by default). An SF3 is turned into the SF2 it
  /// stands for first (a few seconds: [onUnpack] tells its samples done out
  /// of all), unless that file is in the library already; kept as it is
  /// when [keepCompressed].
  Future<MidiSoundFontEntry> import(
    Uint8List bytes, {
    String? name,
    void Function(int done, int total)? onUnpack,
  }) async {
    String? originalSha256;
    if (midiSoundFontIsCompressed(bytes)) {
      originalSha256 = sha256.convert(bytes).toString();
      var known = await _fromOriginal(originalSha256);
      if (known != null) {
        return known;
      }
      if (keepCompressed) {
        return _add(
          bytes,
          id: _slug(name ?? MidiSoundFontDefinition.fromBytes(bytes).name),
          name: name,
          compressed: true,
        );
      }
      bytes = await _decompress(bytes, onProgress: onUnpack);
    }
    var soundFont = MidiSoundFont.fromBytes(bytes);
    return _add(
      bytes,
      id: _slug(name ?? soundFont.name),
      name: name,
      originalSha256: originalSha256,
    );
  }

  /// The entry made from the SF3 of SHA-256 [originalSha256], null when none.
  Future<MidiSoundFontEntry?> _fromOriginal(String originalSha256) async =>
      (await list())
          .where((entry) => entry.originalSha256 == originalSha256)
          .firstOrNull;

  /// How much a download keeps in memory before writing it to its part.
  static const _flushSize = 4 * 1024 * 1024;

  File _partFile(String id) =>
      fileSystem.file(fileSystem.path.join(path, '$id.sf2.part'));

  /// The bytes of SoundFont [id] received by a download that did not end
  /// (cancelled, offline): the next download resumes from there. 0 when
  /// none.
  Future<int> partSize(String id) async {
    var part = _partFile(id);
    return await part.exists() ? (await part.stat()).size : 0;
  }

  /// Forgets the bytes of an unfinished download of SoundFont [id].
  Future<void> deletePart(String id) async {
    var part = _partFile(id);
    if (await part.exists()) {
      await part.delete();
    }
  }

  /// Downloads [source], with [onProgress] (bytes received, total when
  /// known). An SF3 is then turned into the SF2 it stands for, with
  /// [onUnpack] (its samples done out of all).
  ///
  /// The locations are tried in order (`source.candidates`): the [soundServer]
  /// of the user first when the source has a path, its url, its mirrors.
  /// One fails on an http error, on [idleTimeout] with no byte, or when its
  /// file is not the one expected (size, SHA-256, git blob id, a SoundFont);
  /// the next is tried then. When none gives the file, the
  /// [MidiSoundFontDownloadException] lists each attempt.
  ///
  /// The bytes go to a part file (`<id>.sf2.part`) as they come, in chunks
  /// of a few MB: [cancel] stops at the next chunk and keeps them, and the
  /// next download asks only for the rest (`Range`; a location answering
  /// the whole file instead starts over).
  Future<MidiSoundFontEntry> download(
    MidiSoundFontSource source, {
    void Function(int received, int? total)? onProgress,
    void Function(int done, int total)? onUnpack,
    MidiSoundFontDownloadCancel? cancel,
    Uri? soundServer,
    Duration idleTimeout = const Duration(seconds: 30),
  }) => _downloadWith(
    source,
    onProgress: onProgress,
    cancel: cancel,
    soundServer: soundServer,
    idleTimeout: idleTimeout,
    keep: (bytes, url) async {
      String? originalSha256;
      var compressed = midiSoundFontIsCompressed(bytes);
      if (compressed && !keepCompressed) {
        originalSha256 = sha256.convert(bytes).toString();
        bytes = await _decompress(bytes, onProgress: onUnpack);
      }
      return _add(
        bytes,
        id: source.id,
        name: source.name,
        source: source,
        url: url,
        originalSha256: originalSha256,
        compressed: compressed && keepCompressed,
      );
    },
  );

  /// The SF2 unpacked from the SF3 [source] (by an app that did not
  /// [keepCompressed], or before it did), null when none.
  Future<MidiSoundFontEntry?> unpacked(MidiSoundFontSource source) async {
    var expectedSha256 = source.sha256;
    if (expectedSha256 == null) {
      return null;
    }
    return (await list())
        .where(
          (entry) =>
              !entry.compressed && entry.originalSha256 == expectedSha256,
        )
        .firstOrNull;
  }

  /// Replaces the SF2 [unpacked] from the SF3 [source] by that SF3,
  /// downloaded again (as [download] does, resumed the same way), when
  /// [keepCompressed]: the same id (the default and the choices made for
  /// it stay), the same sounds (its samples decode the same), its file 9 MB
  /// instead of 32 for GeneralUser GS, played per song. Null when there is
  /// none to replace (or no more once downloaded: deleted meanwhile).
  ///
  /// An app stopped between the two files leaves the SF2 file there: the
  /// next call deletes it.
  Future<MidiSoundFontEntry?> replaceUnpacked(
    MidiSoundFontSource source, {
    void Function(int received, int? total)? onProgress,
    MidiSoundFontDownloadCancel? cancel,
    Uri? soundServer,
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    if (!keepCompressed) {
      return null;
    }
    await _deleteReplaced(source);
    var found = await unpacked(source);
    if (found == null) {
      return null;
    }
    return _downloadWith(
      source,
      onProgress: onProgress,
      cancel: cancel,
      soundServer: soundServer,
      idleTimeout: idleTimeout,
      keep: (bytes, url) async {
        if (!midiSoundFontIsCompressed(bytes)) {
          throw MidiSoundFontDownloadException('not an SF3');
        }
        var info = _Info.ofDefinition(MidiSoundFontDefinition.fromBytes(bytes));
        return _change(() async {
          var index = await _load();
          var entries = _entries(index);
          var at = entries.indexWhere(
            (entry) => entry.id == found.id && !entry.compressed,
          );
          if (at < 0) {
            return null;
          }
          var old = entries[at];
          var entry = MidiSoundFontEntry(
            id: old.id,
            name: old.name,
            size: bytes.length,
            presetCount: info.presetCount,
            sha256: sha256.convert(bytes).toString(),
            copyright: info.copyright,
            author: info.author,
            comments: info.comments,
            url: old.url ?? url.toString(),
            licence: old.licence ?? source.licence,
            compressed: true,
          );
          await _file(old.id, compressed: true).writeAsBytes(bytes);
          entries[at] = entry;
          index['soundFonts'] = [for (var entry in entries) entry._toMap()];
          await _save(index);
          var sf2 = _file(old.id);
          if (await sf2.exists()) {
            await sf2.delete();
          }
          return entry;
        });
      },
    );
  }

  /// The SF2 file left by a [replaceUnpacked] stopped once its SF3 was
  /// kept: deleted.
  Future<void> _deleteReplaced(MidiSoundFontSource source) => _change(() async {
    for (var entry in await list()) {
      if (entry.compressed && entry.sha256 == source.sha256) {
        var sf2 = _file(entry.id);
        if (await sf2.exists()) {
          await sf2.delete();
        }
      }
    }
  });

  /// Downloads [source] from its locations in order, each checked, then
  /// [keep]s it: a location that fails (or whose file [keep] refuses, a
  /// [MidiSoundFontWorkerException] apart) goes on with the next one.
  Future<T> _downloadWith<T>(
    MidiSoundFontSource source, {
    required Future<T> Function(Uint8List bytes, Uri url) keep,
    void Function(int received, int? total)? onProgress,
    MidiSoundFontDownloadCancel? cancel,
    Uri? soundServer,
    required Duration idleTimeout,
  }) async {
    var client = _client ?? http.Client();
    var attempts = <MidiSoundFontDownloadAttempt>[];
    try {
      for (var url in source.candidates(soundServer: soundServer)) {
        Uint8List bytes;
        try {
          bytes = await _fetchPart(
            client,
            url,
            source,
            onProgress: onProgress,
            cancel: cancel,
            idleTimeout: idleTimeout,
          );
        } on MidiSoundFontDownloadCancelledException {
          rethrow;
        } catch (e) {
          attempts.add(MidiSoundFontDownloadAttempt(url, e));
          continue;
        }
        var problem = _problem(bytes, source);
        if (problem != null) {
          // Not the file: none of it is kept.
          await deletePart(source.id);
          attempts.add(MidiSoundFontDownloadAttempt(url, problem));
          continue;
        }
        T kept;
        try {
          kept = await keep(bytes, url);
        } on MidiSoundFontWorkerException {
          // The worker failed (out of memory?), not the file: kept, the
          // next try decodes it again without downloading it.
          rethrow;
        } catch (e) {
          // Not a SoundFont (or an SF3 that does not decode).
          await deletePart(source.id);
          attempts.add(MidiSoundFontDownloadAttempt(url, e));
          continue;
        }
        await deletePart(source.id);
        return kept;
      }
    } finally {
      if (_client == null) {
        client.close();
      }
    }
    if (attempts.length == 1) {
      throw MidiSoundFontDownloadException(
        '${attempts.single}',
        attempts: attempts,
      );
    }
    throw MidiSoundFontDownloadException(
      '${source.id}: no location gave the file',
      attempts: attempts,
    );
  }

  /// Why [bytes] are not the file of [source], null when they are (or when
  /// the source gives nothing to check).
  MidiSoundFontDownloadException? _problem(
    Uint8List bytes,
    MidiSoundFontSource source,
  ) {
    var size = source.size;
    if (size != null && bytes.length != size) {
      return MidiSoundFontDownloadException(
        '${bytes.length} bytes, $size expected',
      );
    }
    var expectedSha256 = source.sha256;
    if (expectedSha256 != null &&
        sha256.convert(bytes).toString() != expectedSha256) {
      return MidiSoundFontDownloadException(
        'not the file expected (SHA-256 $expectedSha256)',
      );
    }
    var gitBlobSha1 = source.gitBlobSha1;
    if (gitBlobSha1 != null && _gitBlobSha1(bytes) != gitBlobSha1) {
      return MidiSoundFontDownloadException(
        'not the file expected (git blob $gitBlobSha1)',
      );
    }
    return null;
  }

  /// The whole file of [source] from [url], into its part (resumed when
  /// there is one), then read back.
  Future<Uint8List> _fetchPart(
    http.Client client,
    Uri url,
    MidiSoundFontSource source, {
    required void Function(int received, int? total)? onProgress,
    required MidiSoundFontDownloadCancel? cancel,
    required Duration idleTimeout,
  }) async {
    var part = _partFile(source.id);
    var have = await partSize(source.id);
    var size = source.size;
    if (size != null && have >= size) {
      if (have == size) {
        return part.readAsBytes();
      }
      await deletePart(source.id);
      have = 0;
    }
    var request = http.Request('GET', url);
    if (have > 0) {
      request.headers['range'] = 'bytes=$have-';
    }
    var response = await client.send(request).timeout(idleTimeout);
    int received;
    int? total;
    if (have > 0 && response.statusCode == 206) {
      received = have;
      total = _contentRangeTotal(response.headers['content-range']) ?? size;
    } else if (response.statusCode == 200) {
      // The whole file: what was there is replaced.
      received = 0;
      total = response.contentLength ?? size;
    } else {
      // Drain it: the connection is reused.
      await response.stream.drain<void>();
      throw MidiSoundFontDownloadException('HTTP ${response.statusCode}');
    }
    await fileSystem.directory(path).create(recursive: true);
    var replace = received == 0;
    var buffer = BytesBuilder(copy: false);
    Future<void> flush() async {
      if (buffer.isEmpty && !replace) {
        return;
      }
      await part.writeAsBytes(
        buffer.takeBytes(),
        mode: replace ? FileMode.write : FileMode.append,
      );
      replace = false;
    }

    if (received > 0) {
      // Resumed: where it starts from.
      onProgress?.call(received, total);
    }
    try {
      await for (var chunk in response.stream.timeout(idleTimeout)) {
        buffer.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
        if (cancel?.isCancelled ?? false) {
          throw MidiSoundFontDownloadCancelledException(source.id, received);
        }
        if (buffer.length >= _flushSize) {
          await flush();
        }
      }
    } finally {
      // What came is kept, for a resume (cancel, timeout, lost network).
      await flush();
    }
    return part.readAsBytes();
  }

  /// SoundFont [source], downloaded first when not in the library yet: the
  /// default SoundFont on first use. Its file already there under another id
  /// (imported) is found without a download when [source] gives its SHA-256,
  /// or its size and git blob id; otherwise it is downloaded, then
  /// recognized.
  Future<MidiSoundFontEntry> ensure(
    MidiSoundFontSource source, {
    void Function(int received, int? total)? onProgress,
    void Function(int done, int total)? onUnpack,
    MidiSoundFontDownloadCancel? cancel,
    Uri? soundServer,
  }) async =>
      await entry(source.id) ??
      await sameFile(source) ??
      await download(
        source,
        onProgress: onProgress,
        onUnpack: onUnpack,
        cancel: cancel,
        soundServer: soundServer,
      );

  /// The entry holding the file of [source] (its SHA-256, or its size and
  /// git blob id), null when none (or when the source gives neither).
  Future<MidiSoundFontEntry?> sameFile(MidiSoundFontSource source) async {
    var expectedSha256 = source.sha256;
    if (expectedSha256 != null) {
      for (var entry in await list()) {
        // An SF3 is kept as its SF2: the file it was made from.
        if (entry.sha256 == expectedSha256 ||
            entry.originalSha256 == expectedSha256) {
          return entry;
        }
      }
      return null;
    }
    var size = source.size;
    var gitBlobSha1 = source.gitBlobSha1;
    if (size == null || gitBlobSha1 == null) {
      return null;
    }
    for (var entry in await list()) {
      if (entry.size == size &&
          _gitBlobSha1(await read(entry.id)) == gitBlobSha1) {
        return entry;
      }
    }
    return null;
  }

  /// Deletes SoundFont [id] (not the built-in one); the default goes back
  /// to the built-in one when it was the default.
  Future<void> delete(String id) async {
    if (id == builtInId) {
      throw ArgumentError.value(id, 'id', 'the built-in SoundFont stays');
    }
    await _change(() async {
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
      for (var file in [_file(id), _file(id, compressed: true)]) {
        if (await file.exists()) {
          await file.delete();
        }
      }
    });
  }
}

/// The total of a `Content-Range` header (`bytes 100-199/1000`), null when
/// unknown.
int? _contentRangeTotal(String? contentRange) {
  if (contentRange == null) {
    return null;
  }
  var slash = contentRange.lastIndexOf('/');
  return slash < 0 ? null : int.tryParse(contentRange.substring(slash + 1));
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

/// What an entry keeps of a SoundFont, read whole (an SF2) or from its
/// definition (an SF3 kept).
class _Info {
  final String name;
  final int presetCount;
  final String copyright;
  final String author;
  final String comments;

  _Info.ofSoundFont(MidiSoundFont soundFont)
    : name = soundFont.name,
      presetCount = soundFont.presets.length,
      copyright = soundFont.copyright,
      author = soundFont.author,
      comments = soundFont.comments;

  _Info.ofDefinition(MidiSoundFontDefinition definition)
    : name = definition.name,
      presetCount = definition.presets.length,
      copyright = definition.copyright,
      author = definition.author,
      comments = definition.comments;
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
