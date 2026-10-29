const audioContext = new AudioContext();

// Create a script processor node to process audio data
const scriptProcessor = audioContext.createScriptProcessor(4096, 1, 1);

// Create a delay node to introduce a 2-second delay
const delayNode = audioContext.createDelay(2);
delayNode.delayTime.value = 2;

// Create a gain node to adjust the output volume
const gainNode = audioContext.createGain();

// Connect the nodes together
scriptProcessor.connect(delayNode);
delayNode.connect(gainNode);
gainNode.connect(audioContext.destination);

// Get the user's audio input
navigator.mediaDevices.getUserMedia({ audio: true })
    .then(stream => {
        const mediaStreamSource = audioContext.createMediaStreamSource(stream);
        mediaStreamSource.connect(scriptProcessor);
    })
    .catch(error => {
        console.error('Error accessing microphone:', error);
    });

// Process the audio data in the script processor
scriptProcessor.onaudioprocess = (audioProcessingEvent) => {
    const inputBuffer = audioProcessingEvent.inputBuffer;
    const outputBuffer = audioProcessingEvent.outputBuffer;

    for (let channel = 0; channel < outputBuffer.numberOfChannels; channel++) {
        const inputData = inputBuffer.getChannelData(channel);
        const outputData = outputBuffer.getChannelData(channel);

        // Copy input data to output data with a 2-second delay
        outputData.set(inputData);
    }
};