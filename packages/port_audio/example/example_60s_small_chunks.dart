import 'package:tekartik_common_utils/common_utils_import.dart';

import 'example_3s_small_chunks.dart';
import 'example_sound.dart';

Future<void> main(List<String> args) async {
  await streamFile(await exampleWavPath(seconds: 60));
}
