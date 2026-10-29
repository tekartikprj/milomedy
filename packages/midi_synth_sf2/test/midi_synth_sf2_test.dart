import 'dart:math' as math;
import 'dart:typed_data';

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';

const _rate = 44100;

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// The zero crossings a second of [samples].
double _crossingsPerSecond(List<double> samples) {
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    if ((samples[i - 1] < 0) != (samples[i] < 0)) {
      crossings++;
    }
  }
  return crossings * _rate / samples.length;
}

/// The first frame of [samples] above [threshold].
int _onset(List<double> samples, [double threshold = 1e-6]) {
  for (var i = 0; i < samples.length; i++) {
    if (samples[i].abs() > threshold) {
      return i;
    }
  }
  return -1;
}

final _soundFont = MidiSoundFont.fromBytes(midiTinySoundFontBytes());

/// A synth with no reverb nor chorus, the samples as they are.
MidiSoundFontSynth _dry() =>
    MidiSoundFontSynth(_soundFont, reverbAndChorus: false);

Float32List _render(MidiSynth synth, int frames) {
  var left = Float32List(frames);
  var right = Float32List(frames);
  synth.render(left, right, 0, frames);
  return left;
}

void main() {
  group('sound font', () {
    test('the tiny one: info and presets', () {
      expect(_soundFont.name, 'Tiny test SoundFont');
      expect(_soundFont.copyright, '');
      expect(
        [
          for (var preset in _soundFont.presets)
            (preset.bank, preset.program, preset.name),
        ],
        [(0, 0, 'Sine'), (128, 0, 'Noise')],
      );
      expect(_soundFont.presetName(128, 0), 'Noise');
      expect(_soundFont.presetName(0, 5), isNull);
    });

    test('the same bytes everywhere', () {
      var bytes = midiTinySoundFontBytes();
      expect(bytes.length, 9774);
      var sum = 0;
      for (var byte in bytes) {
        sum = (sum * 31 + byte) % 1000003;
      }
      expect(sum, _bytesChecksum);
    });
  });

  group('synth', () {
    test('a sine at the pitch of its key', () {
      var synth = _dry()..send(midiNoteOn, 69, 127);
      expect(synth.activeVoiceCount, 1);
      expect(_crossingsPerSecond(_render(synth, _rate)), closeTo(880, 5));
      synth
        ..send(midiNoteOff, 69)
        ..send(midiNoteOn, 81, 127);
      _render(synth, _rate ~/ 2);
      // An octave up, the released note gone.
      expect(synth.activeVoiceCount, 1);
      expect(_crossingsPerSecond(_render(synth, _rate)), closeTo(1760, 10));
    });

    test('the release, the velocity, the volume', () {
      var synth = _dry()..send(midiNoteOn, 69, 127);
      var loud = _peak(_render(synth, _rate ~/ 4));
      expect(loud, inExclusiveRange(0.05, 1));
      synth.send(midiNoteOff, 69);
      // A release of 0.1 s.
      var release = _render(synth, _rate ~/ 2);
      expect(_peak(release.sublist(0, 441)), greaterThan(0.01));
      expect(_peak(release.sublist(_rate ~/ 4)), lessThan(0.001));
      expect(synth.activeVoiceCount, 0);
      synth.send(midiNoteOn, 69, 32);
      expect(_peak(_render(synth, _rate ~/ 4)), lessThan(loud / 2));
      synth
        ..reset()
        ..send(midiControlChange, midiControllerVolume, 0)
        ..send(midiNoteOn, 69, 127);
      expect(_peak(_render(synth, _rate ~/ 4)), lessThan(0.001));
    });

    test('the drum kit on the percussion channel', () {
      var synth = _dry()
        ..send(midiNoteOn | midiPercussionChannel, midiKeyHiWoodBlock, 127);
      var noise = _render(synth, _rate ~/ 2);
      expect(_peak(noise.sublist(0, 4410)), greaterThan(0.05));
      // Not a sine: many more crossings.
      expect(_crossingsPerSecond(noise.sublist(0, 4000)), greaterThan(5000));
      // 0.1 s, not looped.
      expect(_peak(noise.sublist(_rate ~/ 4)), lessThan(0.001));
    });

    test('render fills the range asked', () {
      var synth = _dry()..send(midiNoteOn, 69, 127);
      var left = Float32List(300)..fillRange(0, 300, 5);
      var right = Float32List(300)..fillRange(0, 300, 5);
      synth.render(left, right, 100, 100);
      expect(left.sublist(0, 100), everyElement(5));
      expect(left.sublist(200), everyElement(5));
      expect(_peak(left.sublist(100, 200)), lessThan(1));
    });
  });

  group('engine', () {
    test('a note in the block of 64 frames of its frame', () {
      var engine = MidiEngine(sampleRate: _rate, synths: [_dry()])
        ..load(
          MidiTimeline(
            notes: const [
              MidiTimelineNote(start: 0.25, duration: 0.25, key: 69),
            ],
          ),
        );
      var left = engine.render(_rate).left.single;
      var frame = (0.25 * _rate).round();
      expect(_onset(left), inInclusiveRange(frame, frame + 64));
    });

    test('fingerprint (the same samples on every platform)', () {
      var timeline = MidiTimeline(
        notes: const [
          MidiTimelineNote(start: 0, duration: 0.3, key: 69, velocity: 100),
          MidiTimelineNote(start: 0.1, duration: 0.3, key: 76, velocity: 80),
          MidiTimelineNote(
            start: 0.2,
            duration: 0.1,
            key: 36,
            channel: midiPercussionChannel,
          ),
        ],
      );
      // With the reverb and the chorus.
      MidiEngine engine() => MidiEngine(
        sampleRate: _rate,
        synths: [MidiSoundFontSynth(_soundFont)],
      );
      var samples = midiRenderOffline(engine(), timeline, tail: 0.2);
      expect(midiRenderOffline(engine(), timeline, tail: 0.2), samples);
      var fingerprint = [
        for (var i = 0; i < samples.length; i += 1999) samples[i],
      ];
      expect(fingerprint, hasLength(_fingerprint.length));
      for (var i = 0; i < fingerprint.length; i++) {
        expect(fingerprint[i], closeTo(_fingerprint[i], 1e-5), reason: '$i');
      }
    });
  });
}

const _bytesChecksum = 920283;

/// Every 1999th sample of the fingerprint render, on the VM.
const _fingerprint = <double>[
  0.00000000,
  -0.01217563,
  -0.01728492,
  -0.03202655,
  -0.03912614,
  -0.08428141,
  -0.07464169,
  -0.06736732,
  -0.04832146,
  -0.07953492,
  -0.03780066,
  -0.01595045,
  0.01826214,
  -0.00957425,
  0.04559180,
  0.02133317,
  0.02518806,
  0.00034476,
  -0.01243028,
  0.00382120,
  -0.01228592,
  0.00637309,
  0.00807672,
  0.00578926,
  -0.00231982,
  0.00243099,
  0.00127435,
];
