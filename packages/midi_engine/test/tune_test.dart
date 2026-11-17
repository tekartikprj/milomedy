import 'dart:math' as math;

import 'package:milomedy_midi_engine/midi_engine.dart';
import 'package:milomedy_midi_synth/midi_synth.dart';
import 'package:test/test.dart';

const _rate = 44100;

/// A long sine at 440 Hz (a click that decays slowly), whatever the key.
const _sine = ClickInstrument(
  frequency: 440,
  accentFrequency: 440,
  decay: 100,
  length: 10,
);

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

/// A synth remembering the messages it is sent.
class _Recorder extends DartSynth {
  final messages = <(int, int, int)>[];

  _Recorder() : super(sampleRate: _rate, instrument: _sine, percussion: _sine);

  @override
  void send(int status, int data1, [int data2 = 0]) {
    messages.add((status, data1, data2));
    super.send(status, data1, data2);
  }

  /// The controllers sent.
  Iterable<int> get controllers => messages
      .where((message) => message.$1 & 0xf0 == midiControlChange)
      .map((message) => message.$2);
}

MidiTimelineMessage _control(double time, int controller, int value) =>
    MidiTimelineMessage(
      time: time,
      status: midiControlChange,
      data1: controller,
      data2: value,
    );

/// A note of 4 s on [channel], a volume message (so that a seek resets the
/// controllers of the channel).
MidiTimeline _note({int channel = 0, List<MidiTimelineMessage>? messages}) =>
    MidiTimeline(
      notes: [
        MidiTimelineNote(start: 0, duration: 4, key: 60, channel: channel),
      ],
      messages:
          messages ??
          [
            MidiTimelineMessage(
              time: 0,
              status: midiControlChange | channel,
              data1: midiControllerVolume,
              data2: 127,
            ),
          ],
    );

/// The frequency of [seconds] rendered by [engine], track 0.
double _render(MidiEngine engine, {double seconds = 0.5}) =>
    _frequency(engine.render((seconds * _rate).round()).left.first);

void main() {
  test('a Dart synth: 440 Hz at 442 Hz after +7.85 cents', () {
    var engine = MidiEngine(
      sampleRate: _rate,
      synths: [DartSynth(sampleRate: _rate, instrument: _sine)],
    )..load(_note());
    expect(_render(engine), closeTo(440, 0.01));
    // The click rings its whole length whatever the note off: silenced
    // before each seek.
    engine
      ..tuneCents = 7.85
      ..silence()
      ..seek(0);
    expect(engine.tuneCents, 7.85);
    expect(_render(engine), closeTo(442, 0.05));
    // Again after a seek, whose reset of the controllers resets the tuning.
    engine
      ..silence()
      ..seek(1);
    expect(_render(engine), closeTo(442, 0.05));
    // And at each pass of a loop.
    engine
      ..setLoop(1, 1.5)
      ..silence()
      ..seek(1);
    expect(_render(engine, seconds: 1.2), closeTo(442, 0.05));
    // Back in tune.
    engine
      ..tuneCents = 0
      ..silence()
      ..seek(1);
    expect(_render(engine), closeTo(440, 0.01));
    // The range.
    expect(() => engine.tuneCents = 100.5, throwsArgumentError);
    expect(() => engine.tuneCents = double.nan, throwsArgumentError);
    engine
      ..tuneCents = -100
      ..silence()
      ..seek(1);
    expect(_render(engine), closeTo(440 / math.pow(2, 1 / 12), 0.05));
  });

  test('not the percussion channel', () {
    var engine = MidiEngine(
      sampleRate: _rate,
      synths: [DartSynth(sampleRate: _rate, percussion: _sine)],
    )..tuneCents = 50;
    engine.load(_note(channel: midiPercussionChannel));
    expect(_render(engine), closeTo(440, 0.01));
  });

  test('nothing sent until tuned, then the RPN 1 of each channel', () {
    var synth = _Recorder();
    var engine = MidiEngine(sampleRate: _rate, synths: [synth])
      ..load(_note())
      ..seek(1)
      ..render(1000);
    expect(synth.controllers, isNot(contains(midiControllerRpnMsb)));
    synth.messages.clear();
    engine.tuneCents = 25;
    // Sent at once, to the channel of the timeline: RPN 1, the value, then
    // the null RPN.
    var value = midiFineTuningValue(25);
    expect(synth.messages, [
      (midiControlChange, midiControllerRpnMsb, 0),
      (midiControlChange, midiControllerRpnLsb, 1),
      (midiControlChange, midiControllerDataEntry, value >> 7),
      (midiControlChange, midiControllerDataEntryLsb, value & 0x7f),
      (midiControlChange, midiControllerRpnMsb, 127),
      (midiControlChange, midiControllerRpnLsb, 127),
    ]);
  });

  test('a fine tuning of the timeline gets the sum', () {
    // The timeline tunes its channel 10 cents up (RPN 1), and selects the
    // pitch bend range (RPN 0) after.
    var ten = midiFineTuningValue(10);
    var timeline = _note(
      messages: [
        _control(0, midiControllerRpnMsb, 0),
        _control(0, midiControllerRpnLsb, 1),
        _control(0, midiControllerDataEntry, ten >> 7),
        _control(0, midiControllerDataEntryLsb, ten & 0x7f),
        _control(0, midiControllerRpnLsb, 0),
      ],
    );
    var synth = _Recorder();
    var engine = MidiEngine(sampleRate: _rate, synths: [synth])..load(timeline);
    expect(_render(engine), closeTo(440 * math.pow(2, 10 / 1200), 0.05));
    synth.messages.clear();
    engine
      ..tuneCents = 7.85
      ..silence()
      ..seek(0.5);
    expect(_render(engine), closeTo(440 * math.pow(2, 17.85 / 1200), 0.05));
    // The sum, then the RPN selected by the timeline (0) selected again.
    var sum = midiFineTuningValue(17.85);
    expect(
      synth.messages,
      containsAllInOrder([
        (midiControlChange, midiControllerRpnMsb, 0),
        (midiControlChange, midiControllerRpnLsb, midiRpnFineTuning),
        (midiControlChange, midiControllerDataEntry, sum >> 7),
        (midiControlChange, midiControllerDataEntryLsb, sum & 0x7f),
        (midiControlChange, midiControllerRpnMsb, 0),
        (midiControlChange, midiControllerRpnLsb, 0),
        (midiNoteOn, 60, 100),
      ]),
    );
    // Played from the start: the sum as the timeline sends its own.
    synth.messages.clear();
    engine
      ..silence()
      ..seek(0);
    engine.render(100);
    expect(
      synth.messages,
      containsAllInOrder([
        (midiControlChange, midiControllerDataEntry, sum >> 7),
        (midiControlChange, midiControllerDataEntryLsb, sum & 0x7f),
      ]),
    );
    expect(_render(engine), closeTo(440 * math.pow(2, 17.85 / 1200), 0.05));
  });

  test('the host and its player', () async {
    var player = _InProcessPlayer([const MidiSynthSpec(instrument: 'none')]);
    expect(player.tuneCents, 0);
    player.tuneCents = -12.5;
    expect(player.tuneCents, -12.5);
    expect(player.host.engine.tuneCents, -12.5);
    expect(() => player.tuneCents = 101, throwsArgumentError);
    expect(player.host.engine.tuneCents, -12.5);
    await player.close();
  });
}

/// A player whose host runs here.
class _InProcessPlayer extends MidiHostPlayer {
  late final MidiEngineHost host;

  _InProcessPlayer(List<MidiSynthSpec> synths)
    : super(trackCount: synths.length) {
    host = MidiEngineHost(sampleRate: 8000, synths: synths, send: handleEvent);
  }

  @override
  void sendCommand(Map<String, Object?> command) => host.handle(command);

  @override
  double get clock => 0;
}
