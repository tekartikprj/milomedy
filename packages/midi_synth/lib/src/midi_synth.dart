/// The interface of a MIDI synth, and the MIDI numbers it understands.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A note off message (its channel in the low 4 bits).
const midiNoteOff = 0x80;

/// A note on message (velocity 0 is a note off).
const midiNoteOn = 0x90;

/// A controller change message.
const midiControlChange = 0xB0;

/// A program change message.
const midiProgramChange = 0xC0;

/// A pitch bend message.
const midiPitchBend = 0xE0;

/// The channel volume controller.
const midiControllerVolume = 7;

/// The channel pan controller.
const midiControllerPan = 10;

/// The expression controller.
const midiControllerExpression = 11;

/// The sustain pedal controller (on from 64).
const midiControllerSustain = 64;

/// The data entry controller: the high 7 bits of the parameter that an RPN
/// selected.
const midiControllerDataEntry = 6;

/// The data entry controller of the low 7 bits.
const midiControllerDataEntryLsb = 38;

/// The reverb send controller (CC 91), 0 to 127.
const midiControllerReverb = 91;

/// The chorus send controller (CC 93), 0 to 127.
const midiControllerChorus = 93;

/// Selects the low 7 bits of a registered parameter number (RPN).
const midiControllerRpnLsb = 100;

/// Selects the high 7 bits of a registered parameter number (RPN).
const midiControllerRpnMsb = 101;

/// The RPN of the pitch bend range.
const midiRpnPitchBendRange = 0;

/// The RPN of the fine tuning: 14 bits, 8192 in tune, from -100 cents (0)
/// to almost +100 cents (16383).
const midiRpnFineTuning = 1;

/// The RPN of the coarse tuning: semitones, 64 in tune (its high 7 bits).
const midiRpnCoarseTuning = 2;

/// The null RPN (127, 127): the data entry controllers then change nothing.
const midiRpnNull = 0x3fff;

/// The 14-bit value of a fine tuning (RPN 1) of [cents] (-100 to 100,
/// clamped): 8192 in tune, 8192 / 100 a cent.
int midiFineTuningValue(double cents) =>
    (8192 + cents * 8192 / 100).round().clamp(0, 16383);

/// The cents of the 14-bit fine tuning (RPN 1) [value].
double midiFineTuningCents(int value) => (value - 8192) * 100 / 8192;

/// Silences the channel at once.
const midiControllerAllSoundOff = 120;

/// Resets the controllers of the channel (not its volume nor its pan). The
/// SoundFont synth (dart_melty_soundfont) and `DartSynth` reset its tuning
/// too.
const midiControllerResetAll = 121;

/// Releases every note of the channel.
const midiControllerAllNotesOff = 123;

/// The default channel volume (General MIDI).
const midiDefaultVolume = 100;

/// The percussion channel of General MIDI (10, counted from 1).
const midiPercussionChannel = 9;

/// The General MIDI hi wood block.
const midiKeyHiWoodBlock = 76;

/// The General MIDI low wood block.
const midiKeyLowWoodBlock = 77;

/// The frequency of [key] (A4, 69, is [a4] Hz), [cents] above it.
double midiKeyFrequency(num key, {double cents = 0, double a4 = 440}) =>
    a4 * math.pow(2, (key - 69 + cents / 100) / 12).toDouble();

/// A synth: plays the channel messages it is sent, renders stereo frames.
///
/// The engine splits its renders at the frame of each message, so a message
/// is heard from the next frame rendered.
abstract class MidiSynth {
  /// The output sample rate.
  int get sampleRate;

  /// Handles a channel message: [status] with its channel in the low 4 bits,
  /// [data1] and [data2] (0 to 127).
  void send(int status, int data1, [int data2 = 0]);

  /// Silences every voice at once, resets the programs and the controllers.
  void reset();

  /// The voices sounding (their releases included).
  int get activeVoiceCount;

  /// Renders the next [count] frames into [left] and [right] from [start],
  /// replacing what is there.
  void render(Float32List left, Float32List right, int start, int count);
}
