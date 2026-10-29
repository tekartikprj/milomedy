/// A SoundFont (SF2) loaded in memory: its info and its presets, shared by
/// the synths that play it.
library;

import 'dart:typed_data';

import 'package:dart_melty_soundfont/soundfont.dart';

/// A preset of a SoundFont: an instrument, chosen by its bank and program.
class MidiSoundFontPreset {
  /// The bank (128 for the drum kits).
  final int bank;

  /// The program, 0 to 127.
  final int program;

  /// The name.
  final String name;

  /// A preset.
  const MidiSoundFontPreset(this.bank, this.program, this.name);

  @override
  String toString() => 'MidiSoundFontPreset($bank, $program, $name)';
}

/// A SoundFont.
class MidiSoundFont {
  /// The SoundFont of dart_melty_soundfont.
  final SoundFont soundFont;

  /// The presets, by bank then program.
  late final List<MidiSoundFontPreset> presets = _presets();

  List<MidiSoundFontPreset> _presets() {
    var presets = <MidiSoundFontPreset>[
      for (var preset in soundFont.presets)
        MidiSoundFontPreset(preset.bankNumber, preset.patchNumber, preset.name),
    ];
    presets.sort(
      (a, b) => a.bank != b.bank ? a.bank - b.bank : a.program - b.program,
    );
    return List.unmodifiable(presets);
  }

  MidiSoundFont._(this.soundFont);

  /// The SoundFont in [bytes] (an `.sf2` file).
  factory MidiSoundFont.fromBytes(Uint8List bytes) =>
      MidiSoundFont._(SoundFont.fromByteData(ByteData.sublistView(bytes)));

  /// Its name.
  String get name => soundFont.info.bankName;

  /// Its copyright notice, empty when none.
  String get copyright => soundFont.info.copyright;

  /// Its author, empty when none.
  String get author => soundFont.info.author;

  /// Its comments, empty when none.
  String get comments => soundFont.info.comments;

  /// The name of the preset of [bank] and [program], null when none.
  String? presetName(int bank, int program) => presets
      .where((preset) => preset.bank == bank && preset.program == program)
      .firstOrNull
      ?.name;
}
