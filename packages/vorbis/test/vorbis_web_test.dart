@TestOn('browser')
library;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'src/check.dart';

/// The decoder compiled for the web: exact on dart2js (its 32-bit bitwise
/// operators) and dart2wasm.
void main() {
  test('the sine decoded', () async {
    var response = await http.get(Uri.base.resolve('data/sine.ogg'));
    expect(response.statusCode, 200);
    checkSine(response.bodyBytes);
  });
}
