/// What a track plays, as data: sent to an engine host (an AudioWorklet,
/// later an isolate), which builds the synth there.
library;

import 'package:milomedy_midi_synth/midi_synth.dart';

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

/// The synth of a track: a [DartSynth] whose instruments are given by id.
class MidiSynthSpec {
  /// The instrument of every program (a [MidiInstrumentIds] id), none when
  /// null.
  final String? instrument;

  /// The register of the reed treble (its id, `musette`...).
  final String? register;

  /// The instrument of the percussion channel, none when null.
  final String? percussion;

  /// A spec.
  const MidiSynthSpec({this.instrument, this.register, this.percussion});

  /// A metronome: the click on the percussion channel.
  static const metronome = MidiSynthSpec(percussion: MidiInstrumentIds.click);

  /// The spec of [map] (from [toMap]).
  factory MidiSynthSpec.fromMap(Map<Object?, Object?> map) => MidiSynthSpec(
    instrument: map['instrument'] as String?,
    register: map['register'] as String?,
    percussion: map['percussion'] as String?,
  );

  /// As a map.
  Map<String, Object?> toMap() => {
    if (instrument != null) 'instrument': instrument,
    if (register != null) 'register': register,
    if (percussion != null) 'percussion': percussion,
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

  /// The synth at [sampleRate].
  DartSynth build(int sampleRate) => DartSynth(
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
      other.percussion == percussion;

  @override
  int get hashCode => Object.hash(instrument, register, percussion);

  @override
  String toString() => 'MidiSynthSpec(${toMap()})';
}
