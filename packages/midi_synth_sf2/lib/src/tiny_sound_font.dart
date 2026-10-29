/// A tiny SoundFont made in code, for the tests and the examples: no file to
/// download, no licence to check.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The sample rate of the samples: a sine of 100 samples is 440 Hz.
const _sampleRate = 44000;

/// The zero samples the format asks after each sample.
const _guard = 46;

/// The bytes of a tiny SoundFont (SF2):
///
/// - bank 0, program 0, "Sine": a looped sine, 440 Hz on A4 (key 69), a
///   0.1 s release; every program falls back to it;
/// - bank 128, program 0, "Noise": the drum kit, a decaying noise of 0.1 s
///   on every key, not looped.
Uint8List midiTinySoundFontBytes() {
  // The samples: the sine, then the noise (an LCG exact in JS numbers).
  const sineLength = 100;
  const noiseLength = 4400;
  var samples = <int>[
    for (var i = 0; i < sineLength; i++)
      (16000 * math.sin(2 * math.pi * i / sineLength)).round(),
    for (var i = 0; i < _guard; i++) 0,
  ];
  var noiseStart = samples.length;
  var seed = 1;
  for (var i = 0; i < noiseLength; i++) {
    seed = (seed * 75 + 74) % 65537;
    var decay = math.exp(-i / 1000);
    samples.add(((seed - 32768) * 0.5 * decay).round());
  }
  samples.addAll(List.filled(_guard, 0));

  var smpl = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    smpl.setInt16(i * 2, samples[i], Endian.little);
  }

  return _riff('sfbk', [
    _list('INFO', [
      _chunk('ifil', _words([2, 1])),
      _chunk('isng', _string('EMU8000', 8)),
      _chunk('INAM', _string('Tiny test SoundFont', 20)),
    ]),
    _list('sdta', [_chunk('smpl', smpl.buffer.asUint8List())]),
    _list('pdta', [
      _chunk('phdr', [
        ..._presetHeader('Sine', program: 0, bank: 0, bag: 0),
        ..._presetHeader('Noise', program: 0, bank: 128, bag: 1),
        ..._presetHeader('EOP', program: 0, bank: 0, bag: 2),
      ]),
      // Preset bags: a generator each, then the terminal bag.
      _chunk('pbag', _words([0, 0, 1, 0, 2, 0])),
      _chunk('pmod', List.filled(10, 0)),
      _chunk('pgen', _words([_instrument, 0, _instrument, 1, 0, 0])),
      _chunk('inst', [
        ..._name('Sine'),
        ..._words([0]),
        ..._name('Noise'),
        ..._words([1]),
        ..._name('EOI'),
        ..._words([2]),
      ]),
      // Instrument bags: 4 generators for the sine, 3 for the noise.
      _chunk('ibag', _words([0, 0, 4, 0, 7, 0])),
      _chunk('imod', List.filled(10, 0)),
      _chunk(
        'igen',
        _words([
          // The sine: every key, a release of 0.1 s (-3986 timecents),
          // looped.
          _keyRange, 0x7f00,
          _releaseVolEnv, -3986 & 0xffff,
          _sampleModes, 1,
          _sampleId, 0,
          // The noise: every key, not looped.
          _keyRange, 0x7f00,
          _sampleModes, 0,
          _sampleId, 1,
          // The terminal generator.
          0, 0,
        ]),
      ),
      _chunk('shdr', [
        ..._sampleHeader('Sine', 0, sineLength, 0, sineLength, key: 69),
        ..._sampleHeader(
          'Noise',
          noiseStart,
          noiseStart + noiseLength,
          noiseStart,
          noiseStart + noiseLength,
          key: 60,
        ),
        ..._sampleHeader('EOS', 0, 0, 0, 0, key: 0, type: 0, rate: 0),
      ]),
    ]),
  ]);
}

// The generators used.
const _instrument = 41;
const _keyRange = 43;
const _releaseVolEnv = 38;
const _sampleId = 53;
const _sampleModes = 54;

List<int> _presetHeader(
  String name, {
  required int program,
  required int bank,
  required int bag,
}) => [
  ..._name(name),
  ..._words([program, bank, bag]),
  ..._dwords([0, 0, 0]),
];

List<int> _sampleHeader(
  String name,
  int start,
  int end,
  int loopStart,
  int loopEnd, {
  required int key,
  int type = 1,
  int rate = _sampleRate,
}) => [
  ..._name(name),
  ..._dwords([start, end, loopStart, loopEnd, rate]),
  key,
  0,
  ..._words([0, type]),
];

/// [name] in 20 bytes, zero padded.
List<int> _name(String name) => _string(name, 20);

List<int> _string(String text, int length) {
  var bytes = ascii.encode(text);
  return [...bytes, ...List.filled(length - bytes.length, 0)];
}

/// Little endian 16-bit values.
List<int> _words(List<int> values) => [
  for (var value in values) ...[value & 0xff, (value >> 8) & 0xff],
];

/// Little endian 32-bit values.
List<int> _dwords(List<int> values) => [
  for (var value in values) ...[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ],
];

/// A chunk: its id, its size, its data, padded to an even size.
List<int> _chunk(String id, List<int> data) => [
  ...ascii.encode(id),
  ..._dwords([data.length]),
  ...data,
  if (data.length.isOdd) 0,
];

List<int> _list(String type, List<List<int>> chunks) =>
    _chunk('LIST', [...ascii.encode(type), for (var c in chunks) ...c]);

Uint8List _riff(String type, List<List<int>> chunks) => Uint8List.fromList(
  _chunk('RIFF', [...ascii.encode(type), for (var c in chunks) ...c]),
);
