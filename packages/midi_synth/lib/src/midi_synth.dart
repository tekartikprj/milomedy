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

/// Silences the channel at once.
const midiControllerAllSoundOff = 120;

/// Resets the controllers of the channel (not its volume nor its pan).
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
