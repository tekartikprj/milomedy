/// The messages between the page and the SoundFont worker
/// (`sound_font_worker.js`). A worker either turns one SF3 into its SF2 and
/// is then terminated (its memory released at once), or makes the
/// SoundFont of each song from one SoundFont for a session (a sampler).
///
/// - worker → page `ready` {version}: started.
/// - page → worker `decompress` {bytes}: the SF3 (its buffer moved).
/// - worker → page `progress` {done, total}: the samples decoded.
/// - worker → page `result` {bytes}: the SF2 (its buffer moved).
/// - page → worker `open` {bytes, cacheBytes}: the SoundFont of a sampler
///   (its buffer moved), kept until the worker is terminated.
/// - page → worker `samples` {id, samples}: the SF2 of these samples, the
///   answer a `result` {id, bytes}.
/// - worker → page `error` {id, error, format}: failed ([id] of the request
///   of a sampler); [format] when the file is not a valid SoundFont.
library;

/// The file of the worker script in the web folder of an app.
const midiSoundFontWorkerJsFilename = 'sound_font_worker.js';

/// The version of these messages: a worker built for another one is not
/// used (built again by its setup). 2: the sampler messages.
const midiSoundFontWorkerProtocolVersion = 2;

/// Started (worker → page).
const midiSoundFontWorkerMessageReady = 'ready';

/// An SF3 to decompress (page → worker).
const midiSoundFontWorkerMessageDecompress = 'decompress';

/// The samples done (worker → page).
const midiSoundFontWorkerMessageProgress = 'progress';

/// The SF2 (worker → page).
const midiSoundFontWorkerMessageResult = 'result';

/// Failed (worker → page).
const midiSoundFontWorkerMessageError = 'error';

/// The SoundFont of a sampler (page → worker).
const midiSoundFontWorkerMessageOpen = 'open';

/// The SF2 of some samples (page → worker).
const midiSoundFontWorkerMessageSamples = 'samples';
