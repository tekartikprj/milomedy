/// The SoundFonts to download: where, how big, how to check them.
library;

/// A SoundFont to download.
class MidiSoundFontSource {
  /// Its id in the library.
  final String id;

  /// Its name.
  final String name;

  /// Where to download it.
  final Uri url;

  /// Its size in bytes, checked when given.
  final int? size;

  /// The git blob id (SHA-1) of the file in its repository, checked when
  /// given.
  final String? gitBlobSha1;

  /// Its licence, in short, for the user.
  final String licence;

  /// A source.
  const MidiSoundFontSource({
    required this.id,
    required this.name,
    required this.url,
    required this.licence,
    this.size,
    this.gitBlobSha1,
  });

  @override
  String toString() => 'MidiSoundFontSource($id, $url)';
}

/// The id of GeneralUser GS in the library.
const midiGeneralUserGsId = 'generaluser_gs';

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
/// author's download files), checked against the file of version 2.0.3.
MidiSoundFontSource midiGeneralUserGs({required Uri url}) =>
    MidiSoundFontSource(
      id: midiGeneralUserGsId,
      name: 'GeneralUser GS 2.0.3',
      url: url,
      size: 32319396,
      gitBlobSha1: '298b552d2e9d1307e03e5c5c99d2c046aaed9ec3',
      licence:
          'Free for any use, private or commercial, by S. Christian Collins '
          '(https://www.schristiancollins.com/generaluser)',
    );
