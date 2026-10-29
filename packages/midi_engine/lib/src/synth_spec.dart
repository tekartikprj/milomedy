/// What a track plays, as data: sent to an engine host (an AudioWorklet,
/// later an isolate), which builds the synth there.
library;

import 'package:milomedy_midi_synth/midi_synth.dart';

import 'sound_font_support.dart';

/// The instruments written in Dart, by id.
abstract final class MidiInstrumentIds {
  /// The treble reeds of an accordion (with a register).
  static const reed = 'reed';

  /// The bass reeds of an accordion.
  static const reedBass = 'reed_bass';

  /// The chord reeds of an accordion.
  static const reedChord = 'reed_chord';

  /// The metronome click.
  static const click = 'click';
}

/// The synth of a track: a [DartSynth] whose instruments are given by id,
/// or the SoundFont synth of a SoundFont sent to the host.
class MidiSynthSpec {
  /// The instrument of every program (a [MidiInstrumentIds] id), none when
  /// null.
  final String? instrument;

  /// The register of the reed treble (its id, `musette`...).
  final String? register;

  /// The instrument of the percussion channel, none when null.
  final String? percussion;

  /// The id of the SoundFont the track plays (loaded with
  /// `MidiHostPlayer.loadSoundFont`): its 16 channels, the drum kits on the
  /// percussion channel. Silent until the SoundFont is loaded; the
  /// instruments are then ignored.
  final String? soundFont;

  /// The effects of a [soundFont] synth: its reverb and chorus. Each synth
  /// has its own, so many tracks (one per channel) play dry: 16 synths with
  /// their effects render 5 times slower than dry.
  final bool effects;

  /// A spec.
  const MidiSynthSpec({
    this.instrument,
    this.register,
    this.percussion,
    this.soundFont,
    this.effects = true,
  });

  /// A metronome: the click on the percussion channel.
  static const metronome = MidiSynthSpec(percussion: MidiInstrumentIds.click);

  /// The spec of [map] (from [toMap]).
  factory MidiSynthSpec.fromMap(Map<Object?, Object?> map) => MidiSynthSpec(
    instrument: map['instrument'] as String?,
    register: map['register'] as String?,
    percussion: map['percussion'] as String?,
    soundFont: map['soundFont'] as String?,
    effects: map['effects'] as bool? ?? true,
  );

  /// As a map.
  Map<String, Object?> toMap() => {
    if (instrument != null) 'instrument': instrument,
    if (register != null) 'register': register,
    if (percussion != null) 'percussion': percussion,
    if (soundFont != null) 'soundFont': soundFont,
    if (!effects) 'effects': false,
  };

  DartInstrument? _instrument(String? id) => switch (id) {
    MidiInstrumentIds.reed => ReedInstrument.treble(
      register: ReedRegister.byId(register),
    ),
    MidiInstrumentIds.reedBass => ReedInstrument.bass(),
    MidiInstrumentIds.reedChord => ReedInstrument.chord(),
    MidiInstrumentIds.click => const ClickInstrument(),
    _ => null,
  };

  /// The synth at [sampleRate]: a [DartSynth], or a [MidiDeferredSynth]
  /// for a [soundFont] (its synth set when the SoundFont is loaded).
  MidiSynth build(int sampleRate) => soundFont != null
      ? MidiDeferredSynth(sampleRate: sampleRate)
      : DartSynth(
          sampleRate: sampleRate,
          instrument: _instrument(instrument),
          percussion: _instrument(percussion),
        );

  /// Sets the instruments of [synth] (heard from its next notes).
  void applyTo(DartSynth synth) {
    synth
      ..instrument = _instrument(instrument)
      ..percussion = _instrument(percussion);
  }

  @override
  bool operator ==(Object other) =>
      other is MidiSynthSpec &&
      other.instrument == instrument &&
      other.register == register &&
      other.percussion == percussion &&
      other.soundFont == soundFont &&
      other.effects == effects;

  @override
  int get hashCode =>
      Object.hash(instrument, register, percussion, soundFont, effects);

  @override
  String toString() => 'MidiSynthSpec(${toMap()})';
}
