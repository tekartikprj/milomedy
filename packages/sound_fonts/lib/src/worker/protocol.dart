/// The messages between the page and the SoundFont worker
/// (`sound_font_worker.js`): one SF3 turned into its SF2 per worker, which
/// is then terminated (its memory released at once).
///
/// - worker → page `ready` {version}: started.
/// - page → worker `decompress` {bytes}: the SF3 (its buffer moved).
/// - worker → page `progress` {done, total}: the samples decoded.
/// - worker → page `result` {bytes}: the SF2 (its buffer moved).
/// - worker → page `error` {error, format}: failed; [format] when the file
///   is not a valid SF3.
library;

/// The file of the worker script in the web folder of an app.
const midiSoundFontWorkerJsFilename = 'sound_font_worker.js';

/// The version of these messages: a worker built for another one is not
/// used (built again by its setup).
const midiSoundFontWorkerProtocolVersion = 1;

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
