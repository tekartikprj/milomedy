const startButton = document.getElementById('start');
const level = document.getElementById('level');
const status = document.getElementById('status');

// An AudioContext only plays after a user gesture.
startButton.addEventListener('click', async () => {
    startButton.disabled = true;
    try {
        const audioContext = new AudioContext();

        // Load the processor (a module, run on the audio thread) and create
        // its node: one input, one output.
        await audioContext.audioWorklet.addModule('processor.js');
        const workletNode = new AudioWorkletNode(audioContext, 'pass-through');

        // The levels posted by the processor.
        workletNode.port.onmessage = (event) => {
            level.value = Math.min(1, event.data.level * 4);
        };

        // Create a delay node to introduce a 2-second delay
        const delayNode = audioContext.createDelay(2);
        delayNode.delayTime.value = 2;

        // Create a gain node to adjust the output volume
        const gainNode = audioContext.createGain();

        // Connect the nodes together
        workletNode.connect(delayNode);
        delayNode.connect(gainNode);
        gainNode.connect(audioContext.destination);

        // Get the user's audio input
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        const mediaStreamSource = audioContext.createMediaStreamSource(stream);
        mediaStreamSource.connect(workletNode);
        status.textContent = 'Speak: you are heard 2 seconds later.';
    } catch (error) {
        console.error('Error starting the audio:', error);
        status.textContent = `Error: ${error}`;
        startButton.disabled = false;
    }
});
