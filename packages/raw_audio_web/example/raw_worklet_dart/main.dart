import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart';

final _startButton = document.getElementById('start') as HTMLButtonElement;
final _level = document.getElementById('level') as HTMLMeterElement;
final _status = document.getElementById('status') as HTMLElement;

void main() {
  // An AudioContext only plays after a user gesture.
  _startButton.onclick = (Event _) {
    _start();
  }.toJS;
}

Future<void> _start() async {
  _startButton.disabled = true;
  try {
    var audioContext = AudioContext();

    // Load the processor (a module compiled from processor.dart, run on the
    // audio thread) and create its node: one input, one output.
    await audioContext.audioWorklet.addModule('processor.js').toDart;
    var workletNode = AudioWorkletNode(audioContext, 'pass-through-dart');

    // The levels posted by the processor.
    workletNode.port.onmessage = (MessageEvent event) {
      var level = ((event.data as JSObject)['level'] as JSNumber).toDartDouble;
      _level.value = math.min(1, level * 4);
    }.toJS;

    // Create a delay node to introduce a 2-second delay
    var delayNode = audioContext.createDelay(2);
    delayNode.delayTime.value = 2;

    // Create a gain node to adjust the output volume
    var gainNode = audioContext.createGain();

    // Connect the nodes together
    workletNode.connect(delayNode);
    delayNode.connect(gainNode);
    gainNode.connect(audioContext.destination);

    // Get the user's audio input
    var stream = await window.navigator.mediaDevices
        .getUserMedia(MediaStreamConstraints(audio: true.toJS))
        .toDart;
    var mediaStreamSource = audioContext.createMediaStreamSource(stream);
    mediaStreamSource.connect(workletNode);
    _status.textContent = 'Speak: you are heard 2 seconds later.';
  } catch (error) {
    _status.textContent = 'Error: $error';
    _startButton.disabled = false;
  }
}
