import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The generators used.
const _startOffset = 0;
const _endOffset = 1;
const _instrument = 41;
const _keyRange = 43;
const _velocityRange = 44;
const _sampleId = 53;
const _sampleModes = 54;

/// A generator.
typedef _Gen = (int, int);

_Gen _range(int type, int low, int high) => (type, low | high << 8);

/// The samples: their length, looped or not.
const _samples = [
  ('Low', 200, true),
  ('High soft', 300, true),
  ('High loud', 250, true),
  ('Kick', 400, false),
  ('Snare', 150, false),
  ('Hat', 180, false),
];

/// A SoundFont made in code with what the tiny one lacks, for the tests of
/// the definition and the sampler:
///
/// - instrument "Split" (a global zone, a range of keys, two of
///   velocity): keys 0-59 sample 0; 60-127 sample 1 (velocity 0-63) or 2
///   (64-127, starting 10 frames later);
/// - instrument "Drums": keys 35-36 sample 3, 38 sample 4, 42 sample 5
///   (ending 20 frames earlier);
/// - instrument "Lead": a global zone (keys 40-90), sample 4 looped;
/// - presets 0:0 "Piano" (a global zone, velocity 1-127) Split; 0:5
///   "Lead" Lead; 8:5 "Lead variation" Split; 128:0 "Kit" Drums; 128:16
///   "Kit 2" (keys 30-40) Drums.
Uint8List zonedSoundFontBytes() {
  var frames = <int>[];
  var headers = <List<int>>[];
  for (var (index, (name, length, looped)) in _samples.indexed) {
    var start = frames.length;
    for (var i = 0; i < length; i++) {
      // A different wave each: a sine whose period depends on the sample.
      frames.add(
        (12000 * math.sin(2 * math.pi * i * (index + 1) / length)).round(),
      );
    }
    frames.addAll(List.filled(46, 0));
    headers.add(
      _sampleHeader(
        name,
        start: start,
        end: start + length,
        loopStart: looped ? start + 20 : start,
        loopEnd: looped ? start + length - 10 : start + length,
      ),
    );
  }
  headers.add(_sampleHeader('EOS', start: 0, end: 0, loopStart: 0, loopEnd: 0));
  var smpl = ByteData(frames.length * 2);
  for (var i = 0; i < frames.length; i++) {
    smpl.setInt16(i * 2, frames[i], Endian.little);
  }

  const loop = (_sampleModes, 1);
  var instruments = <(String, List<List<_Gen>>)>[
    (
      'Split',
      [
        // Global: a key range the zones replace.
        [_range(_keyRange, 0, 127)],
        [_range(_keyRange, 0, 59), loop, (_sampleId, 0)],
        [
          _range(_keyRange, 60, 127),
          _range(_velocityRange, 0, 63),
          loop,
          (_sampleId, 1),
        ],
        [
          _range(_keyRange, 60, 127),
          _range(_velocityRange, 64, 127),
          (_startOffset, 10),
          loop,
          (_sampleId, 2),
        ],
      ],
    ),
    (
      'Drums',
      [
        [_range(_keyRange, 35, 36), (_sampleId, 3)],
        [_range(_keyRange, 38, 38), (_sampleId, 4)],
        [_range(_keyRange, 42, 42), (_endOffset, -20 & 0xffff), (_sampleId, 5)],
      ],
    ),
    (
      'Lead',
      [
        [_range(_keyRange, 40, 90)],
        [loop, (_sampleId, 4)],
      ],
    ),
  ];
  var presets = <(String, int, int, List<List<_Gen>>)>[
    (
      'Piano',
      0,
      0,
      [
        [_range(_velocityRange, 1, 127)],
        [(_instrument, 0)],
      ],
    ),
    (
      'Lead',
      0,
      5,
      [
        [(_instrument, 2)],
      ],
    ),
    (
      'Lead variation',
      8,
      5,
      [
        [(_instrument, 0)],
      ],
    ),
    (
      'Kit',
      128,
      0,
      [
        [(_instrument, 1)],
      ],
    ),
    (
      'Kit 2',
      128,
      16,
      [
        [_range(_keyRange, 30, 40), (_instrument, 1)],
      ],
    ),
  ];

  // Bags and generators of a list of elements, each a list of zones.
  (List<int>, List<int>, List<int>) zones(List<List<List<_Gen>>> elements) {
    var bags = <int>[];
    var gens = <int>[];
    var firsts = <int>[];
    var genCount = 0;
    for (var element in elements) {
      firsts.add(bags.length ~/ 2);
      for (var zone in element) {
        bags.addAll([genCount, 0]);
        for (var (type, value) in zone) {
          gens.addAll([type, value]);
          genCount++;
        }
      }
    }
    firsts.add(bags.length ~/ 2);
    bags.addAll([genCount, 0]);
    gens.addAll([0, 0]);
    return (bags, gens, firsts);
  }

  var (ibag, igen, instrumentFirsts) = zones([
    for (var (_, zones) in instruments) zones,
  ]);
  var (pbag, pgen, presetFirsts) = zones([
    for (var (_, _, _, zones) in presets) zones,
  ]);

  return _riff('sfbk', [
    _list('INFO', [
      _chunk('ifil', _words([2, 1])),
      _chunk('isng', _string('EMU8000', 8)),
      _chunk('INAM', _string('Zoned test SoundFont', 22)),
    ]),
    _list('sdta', [_chunk('smpl', smpl.buffer.asUint8List())]),
    _list('pdta', [
      _chunk('phdr', [
        for (var (i, (name, bank, program, _)) in presets.indexed)
          ..._presetHeader(name, program, bank, presetFirsts[i]),
        ..._presetHeader('EOP', 0, 0, presetFirsts.last),
      ]),
      _chunk('pbag', _words(pbag)),
      _chunk('pmod', List.filled(10, 0)),
      _chunk('pgen', _words(pgen)),
      _chunk('inst', [
        for (var (i, (name, _)) in instruments.indexed) ...[
          ..._string(name, 20),
          ..._words([instrumentFirsts[i]]),
        ],
        ..._string('EOI', 20),
        ..._words([instrumentFirsts.last]),
      ]),
      _chunk('ibag', _words(ibag)),
      _chunk('imod', List.filled(10, 0)),
      _chunk('igen', _words(igen)),
      _chunk('shdr', [for (var header in headers) ...header]),
    ]),
  ]);
}

List<int> _presetHeader(String name, int program, int bank, int bag) => [
  ..._string(name, 20),
  ..._words([program, bank, bag]),
  ...List.filled(12, 0),
];

List<int> _sampleHeader(
  String name, {
  required int start,
  required int end,
  required int loopStart,
  required int loopEnd,
}) => [
  ..._string(name, 20),
  ..._dwords([start, end, loopStart, loopEnd, 44100]),
  60, // original key
  0, // correction
  ..._words([0, 1]), // link, mono
];

List<int> _string(String text, int length) {
  var bytes = ascii.encode(text);
  return [...bytes, ...List.filled(length - bytes.length, 0)];
}

List<int> _words(List<int> values) => [
  for (var value in values) ...[value & 0xff, (value >> 8) & 0xff],
];

List<int> _dwords(List<int> values) => [
  for (var value in values)
    for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xff,
];

List<int> _chunk(String id, List<int> data) => [
  ...ascii.encode(id),
  ..._dwords([data.length]),
  ...data,
  if (data.length.isOdd) 0,
];

List<int> _list(String type, List<List<int>> chunks) =>
    _chunk('LIST', [...ascii.encode(type), for (var chunk in chunks) ...chunk]);

Uint8List _riff(String type, List<List<int>> chunks) => Uint8List.fromList(
  _chunk('RIFF', [...ascii.encode(type), for (var chunk in chunks) ...chunk]),
);
