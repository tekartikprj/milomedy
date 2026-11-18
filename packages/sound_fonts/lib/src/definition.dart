/// The definition of a SoundFont, SF2 or SF3, without its sample frames:
/// its INFO, presets, instruments, zones and sample headers, and the
/// samples a set of notes plays ([MidiSoundFontDefinition.samplesFor]),
/// found the way the synth (dart_melty_soundfont) finds them.
library;

import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';

import 'riff.dart';

/// A note as the synth sees it: the bank and program of its channel when
/// it starts (the bank 128 and up on the percussion channel), its key as
/// played (transposed), its velocity.
typedef MidiSoundFontNote = ({int bank, int program, int key, int velocity});

/// The bank of the drum kits, added to the bank selected on the percussion
/// channel.
const _drumBank = 128;

const _genStartOffset = 0;
const _genEndOffset = 1;
const _genStartLoopOffset = 2;
const _genEndLoopOffset = 3;
const _genStartCoarseOffset = 4;
const _genEndCoarseOffset = 12;
const _genInstrument = 41;
const _genKeyRange = 43;
const _genVelocityRange = 44;
const _genStartLoopCoarseOffset = 45;
const _genEndLoopCoarseOffset = 50;
const _genSampleId = 53;

/// The notes [timeline] plays, as its SoundFont synths see them: the bank
/// and program of each channel of each track (bank 0, program 0 at first,
/// the bank 128 on the percussion channel; CC 0 selects the bank, a program
/// change the program; the messages at an instant before its notes, as the
/// engine sends them), each key moved by [transpose] semitones but on the
/// percussion channel (kept within 0 to 127, as the engine does).
Set<MidiSoundFontNote> midiSoundFontNotes(
  MidiTimeline timeline, {
  int transpose = 0,
}) {
  // By track and channel: (bank, program).
  var state = <int, (int, int)>{};
  (int, int) of(int track, int channel) =>
      state[track * 16 + channel] ??
      (channel == midiPercussionChannel ? _drumBank : 0, 0);
  var messages = timeline.messages;
  var next = 0;
  var notes = <MidiSoundFontNote>{};
  for (var note in timeline.notes) {
    while (next < messages.length && messages[next].time <= note.start) {
      var message = messages[next++];
      var channel = message.channel;
      var key = message.track * 16 + channel;
      var (bank, program) = of(message.track, channel);
      switch (message.status & 0xf0) {
        case 0xb0 when message.data1 == 0:
          state[key] = (
            message.data2 + (channel == midiPercussionChannel ? _drumBank : 0),
            program,
          );
        case 0xc0:
          state[key] = (bank, message.data1);
      }
    }
    var (bank, program) = of(note.track, note.channel);
    notes.add((
      bank: bank,
      program: program,
      key: note.channel == midiPercussionChannel
          ? note.key
          : (note.key + transpose).clamp(0, 127),
      velocity: note.velocity,
    ));
  }
  return notes;
}

/// A zone: its key and velocity ranges, its instrument (a preset zone) or
/// its sample (an instrument zone).
class _Zone {
  final int keyLow;
  final int keyHigh;
  final int velocityLow;
  final int velocityHigh;
  final int target;

  _Zone(
    this.keyLow,
    this.keyHigh,
    this.velocityLow,
    this.velocityHigh,
    this.target,
  );

  bool contains(int key, int velocity) =>
      keyLow <= key &&
      key <= keyHigh &&
      velocityLow <= velocity &&
      velocity <= velocityHigh;
}

/// A sample header of a SoundFont: in an SF2 its frames in the sample data
/// ([start] to [end], loops absolute); in an SF3, for a compressed sample,
/// the bytes of its Ogg stream ([start] to [end]) and its loops from its
/// first frame.
class MidiSoundFontSampleHeader {
  /// Its name.
  final String name;

  /// Its first frame, or the first byte of its stream.
  final int start;

  /// After its last frame, or after its stream.
  final int end;

  /// Its loop start.
  final int loopStart;

  /// Its loop end.
  final int loopEnd;

  /// Its sample rate.
  final int sampleRate;

  /// Its type (mono, left, right, linked; ROM; compressed).
  final int type;

  /// A sample header.
  const MidiSoundFontSampleHeader({
    required this.name,
    required this.start,
    required this.end,
    required this.loopStart,
    required this.loopEnd,
    required this.sampleRate,
    required this.type,
  });

  /// True for an Ogg Vorbis stream (SF3).
  bool get compressed => type & 0x10 != 0;

  /// True for a sample in ROM, not in the file.
  bool get rom => type & soundFontSampleTypeRom != 0;
}

/// The definition of a SoundFont, SF2 or SF3: everything but its sample
/// frames.
class MidiSoundFontDefinition {
  /// Its name (INAM).
  final String name;

  /// Its copyright notice (ICOP), empty when none.
  final String copyright;

  /// Its author (IENG), empty when none.
  final String author;

  /// Its comments (ICMT), empty when none.
  final String comments;

  /// Its sample headers (the terminal one apart), in their order: a sample
  /// is its index there.
  final List<MidiSoundFontSampleHeader> samples;

  /// Its presets, by bank then program.
  final List<MidiSoundFontPreset> presets;

  /// The zones of each preset, by id (`bank << 16 | program`; of two
  /// presets with one id, the last, as the synth).
  final Map<int, List<_Zone>> _presetZones;

  /// The id of the preset played when none matches: the lowest.
  final int? _defaultPresetId;

  /// The zones of each instrument.
  final List<List<_Zone>> _instrumentZones;

  /// The largest address offset of an instrument zone, in frames: how far
  /// from its sample a zone can read.
  final int addressOffsetBound;

  MidiSoundFontDefinition._({
    required this.name,
    required this.copyright,
    required this.author,
    required this.comments,
    required this.samples,
    required this.presets,
    required this._presetZones,
    required this._defaultPresetId,
    required this._instrumentZones,
    required this.addressOffsetBound,
  });

  /// The definition of the SoundFont [bytes] (SF2 or SF3); its sample data
  /// is not read. A [FormatException] when it is not a SoundFont.
  factory MidiSoundFontDefinition.fromBytes(Uint8List bytes) =>
      MidiSoundFontDefinition.ofBank(soundFontReadBank(bytes));

  /// The definition of [bank], read by `soundFontReadBank`.
  factory MidiSoundFontDefinition.ofBank(SoundFontChunk bank) {
    var info = bank.find('INFO');
    String text(String id) {
      var chunk = info?.find(id);
      return chunk == null ? '' : _string(chunk.data);
    }

    var pdta = bank.find('pdta');
    ByteData records(String id, int size) {
      var chunk = pdta?.find(id);
      if (chunk == null || chunk.data.length < size) {
        throw FormatException('SoundFont: no $id');
      }
      return ByteData.sublistView(
        chunk.data,
        0,
        chunk.data.length - chunk.data.length % size,
      );
    }

    var phdr = records('phdr', 38);
    var pbag = records('pbag', 4);
    var pgen = records('pgen', 4);
    var inst = records('inst', 22);
    var ibag = records('ibag', 4);
    var igen = records('igen', 4);
    var shdr = soundFontSampleHeaders(bank);

    // The generators of each zone, from its bag to the next.
    List<List<(int, int)>> zones(ByteData bags, ByteData gens) {
      var count = bags.lengthInBytes ~/ 4;
      var genCount = gens.lengthInBytes ~/ 4;
      return [
        for (var b = 0; b + 1 < count; b++)
          [
            for (
              var g = bags.getUint16(b * 4, Endian.little);
              g < bags.getUint16(b * 4 + 4, Endian.little) && g < genCount;
              g++
            )
              (
                gens.getUint16(g * 4, Endian.little),
                gens.getUint16(g * 4 + 2, Endian.little),
              ),
          ],
      ];
    }

    // The zones of an element (a preset, an instrument) from its first bag
    // to the next element's, the first one global when it does not end on
    // [targetGen]: the base of the others (the synth's rules).
    List<_Zone> regions(
      List<List<(int, int)>> allZones,
      int first,
      int end,
      int targetGen,
    ) {
      if (first >= end || end > allZones.length) {
        return const [];
      }
      var span = allZones.sublist(first, end);
      List<(int, int)>? global;
      if (span.first.isEmpty || span.first.last.$1 != targetGen) {
        global = span.first;
        span = span.sublist(1);
      }
      return [
        for (var local in span)
          () {
            var keyRange = 0x7f00;
            var velocityRange = 0x7f00;
            var target = 0;
            for (var (type, value) in [...?global, ...local]) {
              if (type == _genKeyRange) {
                keyRange = value;
              } else if (type == _genVelocityRange) {
                velocityRange = value;
              } else if (type == targetGen) {
                target = value;
              }
            }
            return _Zone(
              keyRange & 0xff,
              (keyRange >> 8) & 0xff,
              velocityRange & 0xff,
              (velocityRange >> 8) & 0xff,
              target,
            );
          }(),
      ];
    }

    var presetBagZones = zones(pbag, pgen);
    var instrumentBagZones = zones(ibag, igen);

    var instrumentCount = inst.lengthInBytes ~/ 22 - 1;
    var instrumentZones = [
      for (var i = 0; i < instrumentCount; i++)
        regions(
          instrumentBagZones,
          inst.getUint16(i * 22 + 20, Endian.little),
          inst.getUint16(i * 22 + 42, Endian.little),
          _genSampleId,
        ),
    ];

    var presetCount = phdr.lengthInBytes ~/ 38 - 1;
    var presetZones = <int, List<_Zone>>{};
    var presets = <MidiSoundFontPreset>[];
    int? defaultPresetId;
    for (var p = 0; p < presetCount; p++) {
      var o = p * 38;
      var program = phdr.getUint16(o + 20, Endian.little);
      var bankNumber = phdr.getUint16(o + 22, Endian.little);
      var id = bankNumber << 16 | program;
      presetZones[id] = regions(
        presetBagZones,
        phdr.getUint16(o + 24, Endian.little),
        phdr.getUint16(o + 38 + 24, Endian.little),
        _genInstrument,
      );
      if (defaultPresetId == null || id < defaultPresetId) {
        defaultPresetId = id;
      }
      presets.add(
        MidiSoundFontPreset(
          bankNumber,
          program,
          _string(Uint8List.sublistView(phdr, o, o + 20)),
        ),
      );
    }
    presets.sort(
      (a, b) => a.bank != b.bank ? a.bank - b.bank : a.program - b.program,
    );

    // The farthest an instrument zone reads from its sample.
    var fine = 0;
    var coarse = 0;
    for (var g = 0; g < igen.lengthInBytes ~/ 4; g++) {
      var type = igen.getUint16(g * 4, Endian.little);
      var value = igen.getInt16(g * 4 + 2, Endian.little).abs();
      switch (type) {
        case _genStartOffset ||
            _genEndOffset ||
            _genStartLoopOffset ||
            _genEndLoopOffset:
          if (value > fine) {
            fine = value;
          }
        case _genStartCoarseOffset ||
            _genEndCoarseOffset ||
            _genStartLoopCoarseOffset ||
            _genEndLoopCoarseOffset:
          if (value > coarse) {
            coarse = value;
          }
      }
    }

    var sampleCount = shdr.lengthInBytes ~/ soundFontHeaderSize - 1;
    return MidiSoundFontDefinition._(
      name: text('INAM'),
      copyright: text('ICOP'),
      author: text('IENG'),
      comments: text('ICMT'),
      samples: List.unmodifiable([
        for (var i = 0; i < sampleCount; i++)
          () {
            var o = i * soundFontHeaderSize;
            int at(int offset) => shdr.getUint32(o + offset, Endian.little);
            return MidiSoundFontSampleHeader(
              name: _string(Uint8List.sublistView(shdr, o, o + 20)),
              start: at(20),
              end: at(24),
              loopStart: at(28),
              loopEnd: at(32),
              sampleRate: at(36),
              type: shdr.getUint16(o + 44, Endian.little),
            );
          }(),
      ]),
      presets: List.unmodifiable(presets),
      presetZones: presetZones,
      defaultPresetId: defaultPresetId,
      instrumentZones: instrumentZones,
      addressOffsetBound: fine + coarse * 32768,
    );
  }

  /// True when one of its samples is compressed (an SF3).
  bool get compressed => samples.any((sample) => sample.compressed);

  /// The samples [notes] play: for each, the preset of its bank and program
  /// (else the same program in bank 0, or for a drum bank the standard kit
  /// 128:0; else the lowest preset), its zones holding the key and the
  /// velocity, then their instrument's zones holding them.
  Set<int> samplesFor(Iterable<MidiSoundFontNote> notes) {
    var found = <int>{};
    for (var note in notes) {
      var zones =
          _presetZones[note.bank << 16 | note.program] ??
          _presetZones[note.bank < _drumBank
              ? note.program
              : _drumBank << 16] ??
          _presetZones[_defaultPresetId];
      for (var zone in zones ?? const <_Zone>[]) {
        if (!zone.contains(note.key, note.velocity) ||
            zone.target >= _instrumentZones.length) {
          continue;
        }
        for (var instrumentZone in _instrumentZones[zone.target]) {
          if (instrumentZone.contains(note.key, note.velocity) &&
              instrumentZone.target < samples.length) {
            found.add(instrumentZone.target);
          }
        }
      }
    }
    return found;
  }
}

/// A fixed length string of a SoundFont: its bytes as Latin-1, the zeros
/// removed (as the synth reads them).
String _string(Uint8List bytes) =>
    String.fromCharCodes(bytes.where((code) => code != 0));
