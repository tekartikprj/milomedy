/// The SoundFonts to download: where, how big, how to check them.
library;

/// A SoundFont to download.
class MidiSoundFontSource {
  /// Its id in the library.
  final String id;

  /// Its name.
  final String name;

  /// Where to download it, tried first.
  final Uri url;

  /// Other locations of the same file (mirrors), tried in order after
  /// [url] when it fails: any url serving the bytes of [sha256] (or of
  /// [size] and [gitBlobSha1]) is safe, the file is checked whatever the
  /// location.
  final List<Uri> locations;

  /// Its path below a sound server (`public/sound_fonts/<sha256>/x.sf2`):
  /// a server of the user's choice serving the same layout is tried first
  /// (`download(soundServer:)`). Null: not served by a sound server.
  final String? path;

  /// Its size in bytes, checked when given.
  final int? size;

  /// The SHA-256 of its bytes (hex), checked when given.
  final String? sha256;

  /// The git blob id (SHA-1) of the file in its repository, checked when
  /// given.
  final String? gitBlobSha1;

  /// Its licence, in short, for the user.
  final String licence;

  /// Where the whole licence text is (a path below the sound server or the
  /// catalog, or an absolute url), null when unknown.
  final String? licenceUrl;

  /// Its version, null when unknown.
  final String? version;

  /// Its number of presets, null when unknown (shown before a download).
  final int? presetCount;

  /// True for an SF3 (its samples compressed): the library keeps the SF2 it
  /// stands for. [size] and [sha256] are those of the SF3.
  final bool compressed;

  /// The id of another source with the same sounds (an SF2 and its SF3): an
  /// app offering both offers one only once the other is installed.
  final String? sameAs;

  /// A source.
  const MidiSoundFontSource({
    required this.id,
    required this.name,
    required this.url,
    required this.licence,
    this.size,
    this.gitBlobSha1,
    this.sha256,
    this.locations = const [],
    this.path,
    this.licenceUrl,
    this.version,
    this.presetCount,
    this.compressed = false,
    this.sameAs,
  });

  /// The urls tried for a download, in order: the [path] below
  /// [soundServer] (when both are given), [url], then [locations]; each
  /// once.
  List<Uri> candidates({Uri? soundServer}) {
    var path = this.path;
    return {
      if (soundServer != null && path != null)
        midiSoundServerUri(soundServer, path),
      url,
      ...locations,
    }.toList();
  }

  @override
  String toString() => 'MidiSoundFontSource($id, $url)';
}

/// The url of [path] (`public/sound_fonts/...`) below the sound server
/// [soundServer] (`http://localhost:8095`, `https://example.com/mirror/`):
/// its path segments followed by those of [path].
Uri midiSoundServerUri(Uri soundServer, String path) => soundServer.replace(
  pathSegments: [
    ...soundServer.pathSegments.where((segment) => segment.isNotEmpty),
    ...path.split('/').where((segment) => segment.isNotEmpty),
  ],
);

/// The id of GeneralUser GS in the library.
const midiGeneralUserGsId = 'generaluser_gs';

/// The SHA-256 of GeneralUser GS 2.0.3.
const midiGeneralUserGsSha256 =
    '9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe';

/// GeneralUser GS 2.0.3 in its repository (mrbumpy409/GeneralUser-GS), at
/// the commit of that version: for development and tools.
///
/// Its licence asks not to link to the author's download files: an app
/// downloads a copy it hosts ([midiGeneralUserGs]).
final midiGeneralUserGsUpstreamUrl = Uri.parse(
  'https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/'
  '97049183643d5fc5a9322a69c5b09efb667c6c3a/GeneralUser-GS.sf2',
);

/// GeneralUser GS 2.0.3 by S. Christian Collins, the default SoundFont: a
/// General MIDI and GS bank, 261 presets and 13 drum kits, 32 MB. Downloaded
/// from [url], a copy the app hosts (its licence asks not to link to the
/// author's download files), then from [locations]; checked against the
/// file of version 2.0.3 (its size, its SHA-256 and its git blob id).
/// [path] is where a sound server keeps it.
MidiSoundFontSource midiGeneralUserGs({
  required Uri url,
  List<Uri> locations = const [],
  String? path,
}) => MidiSoundFontSource(
  id: midiGeneralUserGsId,
  name: 'GeneralUser GS 2.0.3',
  url: url,
  locations: locations,
  path: path,
  size: 32319396,
  sha256: midiGeneralUserGsSha256,
  gitBlobSha1: '298b552d2e9d1307e03e5c5c99d2c046aaed9ec3',
  version: '2.0.3',
  presetCount: 287,
  sameAs: midiGeneralUserGsSf3Id,
  licence:
      'Free for any use, private or commercial, by S. Christian Collins '
      '(https://www.schristiancollins.com/generaluser)',
);

/// The id of GeneralUser GS 2.0.3 in SF3 in the library.
const midiGeneralUserGsSf3Id = 'generaluser_gs_sf3';

/// The SHA-256 of GeneralUser GS 2.0.3 in SF3 (by
/// `tool/compress_sound_font.dart --quality 6`, ffmpeg's libvorbis).
const midiGeneralUserGsSf3Sha256 =
    '0aec3f5023ff1857c01b4af4ee4881ba24c4b6b1d1bf1e605d88c9a93c299c8f';

/// GeneralUser GS 2.0.3 compressed (SF3, its samples in Ogg Vorbis at
/// quality 6): 9 MB to download instead of 32 MB, the SF2 it stands for
/// kept by the library (the same presets, the samples at a median signal
/// to noise ratio of 32 dB). Made by `tool/compress_sound_font.dart` from
/// the file of [midiGeneralUserGs], its licence allowing a new packaging;
/// downloaded from [url], a copy the app hosts, then from [locations].
MidiSoundFontSource midiGeneralUserGsSf3({
  required Uri url,
  List<Uri> locations = const [],
  String? path,
}) => MidiSoundFontSource(
  id: midiGeneralUserGsSf3Id,
  name: 'GeneralUser GS 2.0.3',
  url: url,
  locations: locations,
  path: path,
  size: 9110502,
  sha256: midiGeneralUserGsSf3Sha256,
  version: '2.0.3',
  presetCount: 287,
  compressed: true,
  sameAs: midiGeneralUserGsId,
  licence:
      'Free for any use, private or commercial, by S. Christian Collins '
      '(https://www.schristiancollins.com/generaluser)',
);
