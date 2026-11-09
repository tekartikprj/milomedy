@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:tekartik_libao/libao.dart';
import 'package:test/test.dart';

/// libao when installed (apt install libao4, brew install libao).
Libao? _openLibao() {
  try {
    return Libao.open();
  } catch (_) {
    return null;
  }
}

void main() {
  final ao = _openLibao();
  group('libao', () {
    setUpAll(() => ao!.initialize());
    tearDownAll(() => ao!.shutdown());

    test('driverInfo of an unknown driver throws, no crash', () {
      final id = ao!.driverId('no_such_driver');
      expect(id, -1);
      expect(() => ao.driverInfo(id), throwsArgumentError);
      expect(() => ao.driverInfo(1 << 20), throwsArgumentError);
    });

    test('options: a list started empty keeps its options', () {
      var options = ao!.appendOptionTo(nullptr, 'id', '0');
      expect(options, isNot(nullptr));
      expect(ao.appendOptionTo(options, 'debug', ''), options);
      expect(ao.appendOption(options, 'quiet', 'yes'), isTrue);
      final found = <String, String>{};
      for (var option = options; option != nullptr; option = option.ref.next) {
        found[option.ref.key.toDartString()] = option.ref.value.toDartString();
      }
      expect(found, {'id': '0', 'debug': '', 'quiet': 'yes'});
      ao.freeOptions(options);
      // appendOption cannot start a list (it would be lost).
      expect(() => ao.appendOption(nullptr, 'debug', ''), throwsArgumentError);
    });
  }, skip: ao == null ? 'libao not installed' : false);
}
