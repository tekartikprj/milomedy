import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_melty_soundfont/reverb.dart';
import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:milomedy_midi_synth_sf2/midi_synth_sf2.dart';
import 'package:test/test.dart';

const _rate = 44100;

final _soundFont = MidiSoundFont.fromBytes(midiTinySoundFontBytes());

double _peak(List<double> samples) =>
    samples.fold(0.0, (peak, s) => math.max(peak, s.abs()));

/// The frequency of the rising zero crossings of [samples] (interpolated).
double _frequency(List<double> samples) {
  double? first;
  var last = 0.0;
  var count = 0;
  for (var i = 1; i < samples.length; i++) {
    var a = samples[i - 1];
    var b = samples[i];
    if (a < 0 && b >= 0) {
      var at = i - 1 + a / (a - b);
      first ??= at;
      last = at;
      count++;
    }
  }
  return (count - 1) * _rate / (last - first!);
}

/// A4 for 4 s on [channel], its volume set (a seek resets the controllers
/// of the channel, its tuning too).
MidiTimeline _a4({int channel = 0}) => MidiTimeline(
  notes: [MidiTimelineNote(start: 0, duration: 4, key: 69, channel: channel)],
  messages: [
    MidiTimelineMessage(
      time: 0,
      status: midiControlChange | channel,
      data1: midiControllerVolume,
      data2: 127,
    ),
  ],
);

void main() {
  test('the shared reverb is melty\'s, sample for sample', () {
    var random = math.Random(1);
    var input = Float32List.fromList([
      for (var i = 0; i < 64 * 300; i++)
        if (i < 5000) (random.nextDouble() - 0.5) * 0.1 else 0,
    ]);
    var melty = Reverb.withSampleRate(_rate);
    var ours = MidiReverb(sampleRate: _rate);
    // In blocks of 64 frames, as melty renders.
    for (var start = 0; start < input.length; start += 64) {
      var block = Float32List.sublistView(input, start, start + 64);
      var meltyLeft = Float32List(64);
      var meltyRight = Float32List(64);
      melty.process(block, meltyLeft, meltyRight);
      var left = Float32List(64);
      var right = Float32List(64);
      ours.process(block, left, right, 64);
      expect(left, meltyLeft, reason: 'left at $start');
      expect(right, meltyRight, reason: 'right at $start');
    }
  });

  test('a dry track on the bus sounds as the synth with its effects', () {
    // The tiny SoundFont has no reverb of its own: the send is the CC 91 of
    // the channel, 40 by default in melty.
    var note = MidiTimeline(
      notes: const [MidiTimelineNote(start: 0, duration: 0.3, key: 69)],
      end: 1,
    );
    Float32List render(MidiSoundFontSynth synth, {double send = 0}) {
      var engine = MidiEngine(sampleRate: _rate, synths: [synth])..load(note);
      var mixdown = MidiStereoMixdown(sampleRate: _rate)
        ..setTrack(0, gain: 1, pan: 0, reverb: send);
      var out = Float32List(_rate);
      for (var start = 0; start < _rate; start += 128) {
        var frames = math.min(128, _rate - start);
        var left = Float32List(frames);
        mixdown.mix(engine.render(frames), left, Float32List(frames));
        out.setRange(start, start + frames, left);
      }
      return out;
    }

    var effects = render(MidiSoundFontSynth(_soundFont));
    var bus = render(
      MidiSoundFontSynth(_soundFont, reverbAndChorus: false),
      send: midiDefaultReverbSend,
    );
    var dry = render(MidiSoundFontSynth(_soundFont, reverbAndChorus: false));
    // The tail after the release (0.3 s + 0.1 s): the reverb alone.
    var tail = (0.5 * _rate).round();
    expect(_peak(dry.sublist(tail)), lessThan(1e-4));
    expect(_peak(effects.sublist(tail)), greaterThan(1e-3));
    // The same while the note holds (until 0.3 s), to the rounding of the
    // floats and the filters flushing to zero.
    var holds = (0.3 * _rate).round();
    var difference = [
      for (var i = 0; i < holds; i++) (effects[i] - bus[i]).abs(),
    ];
    expect(_peak(difference), lessThan(1e-5));
    // The tails close: melty stops feeding its reverb once a voice is under
    // 1e-3 of it, and steps the small changes of gain (its release).
    double energy(List<double> samples) =>
        samples.fold(0.0, (sum, s) => sum + s * s);
    expect(
      energy(bus.sublist(holds)) / energy(effects.sublist(holds)),
      inInclusiveRange(0.75, 1.1),
    );
  });

  group('tuning', () {
    MidiEngine engine() => MidiEngine(
      sampleRate: _rate,
      synths: [MidiSoundFontSynth(_soundFont, reverbAndChorus: false)],
    );

    test('the 440 Hz sine at 442 Hz after +7.85 cents', () {
      var tuned = engine()
        ..tuneCents = 7.85
        ..load(_a4());
      expect(
        _frequency(tuned.render(_rate ~/ 2).left.first.sublist(441)),
        closeTo(442, 0.05),
      );
      // Again after a seek, whose reset of the controllers resets it (after
      // the release of the note released there: 0.1 s).
      tuned.seek(1);
      expect(
        _frequency(tuned.render(_rate ~/ 2).left.first.sublist(_rate ~/ 8)),
        closeTo(442, 0.05),
      );
      // Heard at once while playing: the notes sounding follow.
      tuned.tuneCents = 0;
      tuned.render(64);
      expect(
        _frequency(tuned.render(_rate ~/ 2).left.first),
        closeTo(440, 0.05),
      );
      // In tune by default.
      var inTune = engine()..load(_a4());
      expect(
        _frequency(inTune.render(_rate ~/ 2).left.first.sublist(441)),
        closeTo(440, 0.05),
      );
    });

    test('not the drums of the percussion channel', () {
      Float32List drums(double cents) {
        var drums = engine()
          ..tuneCents = cents
          ..load(_a4(channel: midiPercussionChannel));
        return drums.render(4410).left.first;
      }

      expect(drums(50), drums(0));
    });

    test('through the host', () {
      var host = MidiEngineHost(
        sampleRate: _rate,
        synths: [const MidiSynthSpec(soundFont: 'tiny', effects: false)],
        send: (_) {},
      );
      midiSoundFontRegister();
      host
        ..handle({
          'type': MidiHostCommands.soundFont,
          'id': 'tiny',
          'bytes': midiTinySoundFontBytes(),
        })
        ..handle({
          'type': MidiHostCommands.load,
          'timeline': midiTimelineToMap(_a4()),
        })
        ..handle({'type': MidiHostCommands.tune, 'value': 7.85})
        ..handle({'type': MidiHostCommands.play});
      var left = <double>[];
      for (var i = 0; i < _rate / 2 / 128; i++) {
        var block = Float32List(128);
        host.render(block, Float32List(128), 0);
        left.addAll(block);
      }
      expect(_frequency(left.sublist(441)), closeTo(442, 0.05));
    });
  });
}
