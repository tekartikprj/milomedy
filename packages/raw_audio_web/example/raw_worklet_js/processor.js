// The AudioWorklet module: runs on the audio thread, in an
// AudioWorkletGlobalScope, and is called for each block of 128 frames.
class PassThroughProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.blocks = 0;
        this.sum = 0;
        this.count = 0;
    }

    process(inputs, outputs) {
        const input = inputs[0];
        const output = outputs[0];
        // Copy the input to the output, channel by channel (no input yet:
        // the output stays silent).
        for (let channel = 0; channel < output.length; channel++) {
            const inputData = input[channel] ?? input[0];
            if (inputData) {
                output[channel].set(inputData);
            }
        }
        // The level of the first channel, posted to the page about 20 times
        // a second.
        if (input.length > 0) {
            for (const sample of input[0]) {
                this.sum += sample * sample;
            }
            this.count += input[0].length;
        }
        if (++this.blocks % 16 === 0) {
            const rms = this.count > 0 ? Math.sqrt(this.sum / this.count) : 0;
            this.port.postMessage({ level: rms });
            this.sum = 0;
            this.count = 0;
        }
        // Keep the processor alive.
        return true;
    }
}

registerProcessor('pass-through', PassThroughProcessor);
