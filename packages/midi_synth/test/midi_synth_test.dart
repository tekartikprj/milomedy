import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 8000;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// Renders [frames] frames of [synth], the left channel.
Float32List _render(MidiSynth synth, int frames) {
  var left = Float32List(frames);
  var right = Float32List(frames);
  synth.render(left, right, 0, frames);
  expect(right, left);
  return left;
}

DartSynth _reedSynth() =>
    DartSynth(sampleRate: _rate, instrument: ReedInstrument.treble());

void main() {
  group('reed', () {
    test('wave tables are band limited, normalized and shared', () {
      var tables = ReedWaveTables.of(ReedTimbre.treble);
      expect(identical(ReedWaveTables.of(ReedTimbre.treble), tables), isTrue);
      var low = tables.tableFor(60);
      var high = tables.tableFor(4000);
      expect(_peak(low.sublist(0, ReedWaveTables.size)), closeTo(1, 1e-9));
      expect(low.last, low.first);
      expect(identical(tables.tableFor(61), low), isTrue);
      expect(identical(high, low), isFalse);
      expect(ReedWaveTables.octaveOf(30), 0);
      expect(ReedWaveTables.octaveOf(440), 4);
    });

    test('registers', () {
      var musette = ReedRegister.byId('musette');
      expect(musette.middleRanks, 3);
      expect(musette.hasLow, isFalse);
      var master = ReedRegister.byId('master');
      expect(master.hasLow && master.hasHigh, isTrue);
      expect(master.middleRanks, 2);
      expect(ReedRegister.byId('nope').id, 'clarinet');
      var instrument = ReedInstrument.treble()..register = musette;
      expect(instrument.ranks, musette.ranks);
    });

    test('every register renders in range', () {
      for (var register in reedRegisters) {
        var synth = DartSynth(
          sampleRate: _rate,
          instrument: ReedInstrument.treble(register: register),
        );
        for (var key in [48, 60, 64, 67, 72]) {
          synth.send(midiNoteOn, key, 127);
        }
        var samples = _render(synth, _rate ~/ 4);
        expect(_peak(samples), inExclusiveRange(0.05, 1), reason: register.id);
        expect(samples.any((s) => s.isNaN), isFalse);
      }
    });
  });

  group('dart synth', () {
    test('note on, note off, release', () {
      var synth = _reedSynth();
      expect(_peak(_render(synth, 100)), 0);
      synth.send(midiNoteOn, 69, 100);
      expect(synth.activeVoiceCount, 1);
      var attack = _render(synth, 400);
      // From the first frame, rising.
      expect(attack[0], isNot(0));
      expect(_peak(attack.sublist(0, 50)), lessThan(_peak(attack)));
      synth.send(midiNoteOff, 69);
      // The release: 45 ms.
      var release = _render(synth, 400);
      expect(_peak(release.sublist(0, 100)), greaterThan(0));
      expect(_peak(release.sublist(360)), 0);
      expect(synth.activeVoiceCount, 0);
    });

    test('note on with velocity 0 is a note off', () {
      var synth = _reedSynth()..send(midiNoteOn, 60, 100);
      _render(synth, 100);
      synth.send(midiNoteOn, 60, 0);
      _render(synth, 1000);
      expect(synth.activeVoiceCount, 0);
    });

    test('render replaces, from its start', () {
      var synth = _reedSynth()..send(midiNoteOn, 60, 100);
      var left = Float32List(200)..fillRange(0, 200, 5);
      var right = Float32List(200)..fillRange(0, 200, 5);
      synth.render(left, right, 100, 100);
      expect(left.sublist(0, 100), everyElement(5));
      expect(_peak(left.sublist(100)), lessThan(1));
      expect(right, left);
    });

    test('volume and expression, a square law', () {
      double peakAt(int volume, int expression) {
        var synth = _reedSynth()
          ..send(midiControlChange, midiControllerVolume, volume)
          ..send(midiControlChange, midiControllerExpression, expression)
          ..send(midiNoteOn, 69, 127);
        return _peak(_render(synth, 800));
      }

      var full = peakAt(127, 127);
      expect(peakAt(midiDefaultVolume, 127), closeTo(full * 0.62, 0.01));
      expect(peakAt(127, 0), 0);
      // Changed while the note sounds: heard at once.
      var synth = _reedSynth()..send(midiNoteOn, 69, 127);
      _render(synth, 800);
      synth.send(midiControlChange, midiControllerVolume, 0);
      expect(_peak(_render(synth, 100)), 0);
    });

    test('sustain holds the note offs', () {
      var synth = _reedSynth()
        ..send(midiControlChange, midiControllerSustain, 127)
        ..send(midiNoteOn, 60, 100);
      _render(synth, 100);
      synth.send(midiNoteOff, 60);
      _render(synth, 1000);
      expect(synth.activeVoiceCount, 1);
      synth.send(midiControlChange, midiControllerSustain, 0);
      _render(synth, 1000);
      expect(synth.activeVoiceCount, 0);
    });

    test('all notes off, all sound off, reset', () {
      var synth = _reedSynth()
        ..send(midiNoteOn, 60, 100)
        ..send(midiNoteOn | 1, 64, 100);
      _render(synth, 100);
      synth.send(midiControlChange | 1, midiControllerAllSoundOff);
      expect(synth.activeVoiceCount, 1);
      synth.send(midiControlChange, midiControllerAllNotesOff);
      _render(synth, 1000);
      expect(synth.activeVoiceCount, 0);
      synth
        ..send(midiNoteOn, 60, 100)
        ..send(midiControlChange, midiControllerVolume, 10)
        ..reset();
      expect(synth.activeVoiceCount, 0);
      synth.send(midiNoteOn, 69, 127);
      var reset = _peak(_render(synth, 800));
      expect(reset, greaterThan(0.1));
    });

    test('programs and the percussion channel', () {
      var synth = DartSynth(
        sampleRate: _rate,
        programs: {1: ReedInstrument.chord()},
        percussion: const ClickInstrument(),
      );
      // Program 0 has no instrument.
      synth.send(midiNoteOn, 60, 100);
      expect(synth.activeVoiceCount, 0);
      synth
        ..send(midiProgramChange, 1)
        ..send(midiNoteOn, 60, 100)
        ..send(midiNoteOn | midiPercussionChannel, midiKeyHiWoodBlock, 100);
      expect(synth.activeVoiceCount, 2);
    });
  });

  group('click', () {
    test('its length whatever the note off, its pitch', () {
      var synth = DartSynth(
        sampleRate: _rate,
        percussion: const ClickInstrument(),
      )..send(midiNoteOn | midiPercussionChannel, midiKeyHiWoodBlock, 127);
      var samples = _render(synth, 1);
      synth.send(midiNoteOff | midiPercussionChannel, midiKeyHiWoodBlock);
      samples = Float32List.fromList([...samples, ..._render(synth, 999)]);
      // 60 ms.
      expect(_peak(samples.sublist(480)), 0);
      expect(_peak(samples.sublist(0, 480)), greaterThan(0.2));
      expect(synth.activeVoiceCount, 0);
      // The accent at 1760 Hz: a zero crossing every 1/3520 s.
      var crossings = 0;
      for (var i = 1; i < 480; i++) {
        if ((samples[i - 1] < 0) != (samples[i] < 0)) {
          crossings++;
        }
      }
      expect(crossings, closeTo(1760 * 2 * 0.06, 3));
    });
  });

  test('key frequency', () {
    expect(midiKeyFrequency(69), 440);
    expect(midiKeyFrequency(57), closeTo(220, 1e-9));
    expect(midiKeyFrequency(69, cents: 100), closeTo(466.16, 0.01));
  });
}
