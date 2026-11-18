import 'dart:typed_data';

import 'package:dart_melty_soundfont/preset.dart';
import 'package:dart_melty_soundfont/soundfont.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:milomedy_sound_fonts/sound_fonts.dart';
import 'package:test/test.dart';

import 'src/zoned_sound_font.dart';

/// The samples dart_melty_soundfont plays for [note], from its own
/// structures: the lookup of `Synthesizer.noteOn`.
Set<int> meltySamples(SoundFont soundFont, MidiSoundFontNote note) {
  var lookup = <int, Preset>{};
  Preset? lowest;
  int? lowestId;
  for (var preset in soundFont.presets) {
    var id = preset.bankNumber << 16 | preset.patchNumber;
    lookup[id] = preset;
    if (lowestId == null || id < lowestId) {
      lowest = preset;
      lowestId = id;
    }
  }
  var preset =
      lookup[note.bank << 16 | note.program] ??
      lookup[note.bank < 128 ? note.program : 128 << 16] ??
      lowest!;
  var samples = <int>{};
  for (var presetRegion in preset.regions) {
    if (!presetRegion.contains(note.key, note.velocity)) {
      continue;
    }
    for (var region in presetRegion.instrument.regions) {
      if (region.contains(note.key, note.velocity)) {
        samples.add(
          soundFont.sampleHeaders.indexWhere(
            (sample) => identical(sample, region.sample),
          ),
        );
      }
    }
  }
  return samples;
}

/// Every key, a few velocities, the banks and programs of [soundFont] and
/// some it lacks (the fallbacks).
Iterable<MidiSoundFontNote> notesToTry() sync* {
  for (var bank in [0, 1, 8, 128, 129, 144, 200]) {
    for (var program in [0, 3, 5, 16, 127]) {
      for (var key = 0; key < 128; key++) {
        for (var velocity in [1, 40, 63, 64, 100, 127]) {
          yield (bank: bank, program: program, key: key, velocity: velocity);
        }
      }
    }
  }
}

void main() {
  group('definition', () {
    test('the zoned SoundFont: as the synth reads it', () {
      var bytes = zonedSoundFontBytes();
      var definition = MidiSoundFontDefinition.fromBytes(bytes);
      var soundFont = MidiSoundFont.fromBytes(bytes);
      expect(definition.name, 'Zoned test SoundFont');
      expect(definition.name, soundFont.name);
      expect(definition.compressed, isFalse);
      expect(
        [for (var p in definition.presets) (p.bank, p.program, p.name)],
        [for (var p in soundFont.presets) (p.bank, p.program, p.name)],
      );
      expect(
        [for (var s in definition.samples) s.name],
        ['Low', 'High soft', 'High loud', 'Kick', 'Snare', 'Hat'],
      );
      // The start offset of 10, the end offset of -20.
      expect(definition.addressOffsetBound, 20);
    });

    test('samplesFor: the samples the synth plays, note by note', () {
      var bytes = zonedSoundFontBytes();
      var definition = MidiSoundFontDefinition.fromBytes(bytes);
      var melty = MidiSoundFont.fromBytes(bytes).soundFont;
      var tried = 0;
      for (var note in notesToTry()) {
        expect(
          definition.samplesFor([note]),
          meltySamples(melty, note),
          reason: '$note',
        );
        tried++;
      }
      expect(tried, greaterThan(10000));
    });

    test('samplesFor: zones, fallbacks', () {
      var definition = MidiSoundFontDefinition.fromBytes(zonedSoundFontBytes());
      Set<int> of(int bank, int program, int key, [int velocity = 100]) =>
          definition.samplesFor([
            (bank: bank, program: program, key: key, velocity: velocity),
          ]);
      // Piano: low, high soft, high loud (velocity 0 never plays: 1-127).
      expect(of(0, 0, 40), {0});
      expect(of(0, 0, 70, 30), {1});
      expect(of(0, 0, 70, 90), {2});
      // Lead: its global zone, keys 40 to 90.
      expect(of(0, 5, 39), isEmpty);
      expect(of(0, 5, 60), {4});
      // The variation, then a program missing in bank 8: bank 0.
      expect(of(8, 5, 70, 30), {1});
      expect(of(8, 0, 40), {0});
      // A missing program: the lowest preset, the piano.
      expect(of(0, 3, 40), {0});
      // The kits, and a missing kit: the standard one, 128:0.
      expect(of(128, 0, 36), {3});
      expect(of(128, 16, 42), isEmpty);
      expect(of(128, 16, 38), {4});
      expect(of(129, 0, 42), {5});
      // Several notes at once.
      expect(
        definition.samplesFor([
          (bank: 0, program: 0, key: 40, velocity: 100),
          (bank: 128, program: 0, key: 42, velocity: 100),
        ]),
        {0, 5},
      );
    });

    test('an SF3: the definition of the SF2 it stands for', () async {
      var sf3 = midiTinySoundFontSf3Bytes();
      var sf2 = await midiSoundFontDecompress(sf3);
      var compressed = MidiSoundFontDefinition.fromBytes(sf3);
      var decompressed = MidiSoundFontDefinition.fromBytes(sf2);
      expect(compressed.compressed, isTrue);
      expect(decompressed.compressed, isFalse);
      expect(compressed.name, decompressed.name);
      expect(
        [for (var p in compressed.presets) (p.bank, p.program, p.name)],
        [for (var p in decompressed.presets) (p.bank, p.program, p.name)],
      );
      expect(
        [for (var s in compressed.samples) s.name],
        [for (var s in decompressed.samples) s.name],
      );
      var melty = MidiSoundFont.fromBytes(sf2).soundFont;
      for (var note in notesToTry()) {
        expect(
          compressed.samplesFor([note]),
          meltySamples(melty, note),
          reason: '$note',
        );
      }
    });

    test('not a SoundFont: a FormatException', () {
      expect(
        () => MidiSoundFontDefinition.fromBytes(Uint8List(100)),
        throwsFormatException,
      );
    });
  });

  group('midiSoundFontNotes', () {
    MidiTimelineNote note(
      double start,
      int key, {
      int channel = 0,
      int track = 0,
      int velocity = 100,
    }) => MidiTimelineNote(
      start: start,
      duration: 0.5,
      key: key,
      velocity: velocity,
      channel: channel,
      track: track,
    );
    MidiTimelineMessage program(
      double time,
      int program, {
      int channel = 0,
      int track = 0,
    }) => MidiTimelineMessage(
      time: time,
      status: 0xc0 | channel,
      data1: program,
      track: track,
    );
    MidiTimelineMessage bank(
      double time,
      int bank, {
      int channel = 0,
      int track = 0,
    }) => MidiTimelineMessage(
      time: time,
      status: 0xb0 | channel,
      data1: 0,
      data2: bank,
      track: track,
    );

    test('banks and programs as the engine sends them', () {
      var timeline = MidiTimeline(
        notes: [
          note(0, 60),
          // A program change at the same instant: before the note.
          note(1, 62),
          note(2, 64, channel: 1),
          note(3, 36, channel: 9),
          note(4, 38, channel: 9),
          // The same channel on another track: its own state.
          note(5, 61, track: 1),
        ],
        messages: [
          program(1, 5),
          bank(1.5, 8, channel: 1),
          program(1.5, 3, channel: 1),
          bank(3.5, 1, channel: 9),
          program(3.5, 16, channel: 9),
          // A controller that is not a bank select: ignored.
          const MidiTimelineMessage(
            time: 0.5,
            status: 0xb0,
            data1: 7,
            data2: 64,
          ),
        ],
      );
      expect(midiSoundFontNotes(timeline), {
        (bank: 0, program: 0, key: 60, velocity: 100),
        (bank: 0, program: 5, key: 62, velocity: 100),
        (bank: 8, program: 3, key: 64, velocity: 100),
        (bank: 128, program: 0, key: 36, velocity: 100),
        (bank: 129, program: 16, key: 38, velocity: 100),
        (bank: 0, program: 0, key: 61, velocity: 100),
      });
    });

    test('transposed, but not the drums, within 0 to 127', () {
      var timeline = MidiTimeline(
        notes: [note(0, 60), note(1, 125), note(2, 36, channel: 9)],
      );
      expect(midiSoundFontNotes(timeline, transpose: 5), {
        (bank: 0, program: 0, key: 65, velocity: 100),
        (bank: 0, program: 0, key: 127, velocity: 100),
        (bank: 128, program: 0, key: 36, velocity: 100),
      });
      expect(
        midiSoundFontNotes(
          MidiTimeline(notes: [note(0, 3)]),
          transpose: -12,
        ).single.key,
        0,
      );
    });
  });
}
