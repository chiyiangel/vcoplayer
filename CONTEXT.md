# VCO Player

VCO Player is a macOS-only headless music player centered on exact local-library playback and remote control.

## Language

**Bit Perfect Playback**:
Playback where the audio samples are preserved unchanged from the decoded source through the playback path. It excludes software volume control, EQ, DSP, system mixing, sample-rate conversion, and bit-depth conversion; if the playback chain cannot configure the output path to preserve the source format, playback is rejected or reported as unsupported.
_Avoid_: Lossless playback, hi-fi playback, high-quality playback

**Unsupported Playback**:
The explicit failure state for a file, output device, or playback path that cannot preserve Bit Perfect Playback. It does not trigger automatic output-device changes, sample-rate conversion, automatic skip, or other fallback playback.
_Avoid_: Fallback playback, degraded playback, best effort

**Playback Failure Reason**:
The operator-visible explanation for why playback could not start or continue, with more detailed diagnostics available in the Server CLI output. It distinguishes unsupported files, unsupported output formats, missing output device selection, device-busy conditions, and playback-path failures.
_Avoid_: Silent failure, generic error, crash

**Music Library Root**:
The single local directory boundary supplied when the server starts and containing all music files and folders available to the player. It is not a metadata catalog or imported media database, cannot be changed from the Operator Remote in the MVP, and files outside this real-path boundary are not part of the library.
_Avoid_: Music database, media library, collection

**Playback List**:
The in-memory ordered list of music files for the current server run, including entries before, at, and after Now Playing. Each entry has a runtime identity so repeated files can be selected or deleted independently; the list is ordered by add operations rather than manual reordering, cleared when the server stops, editable except for the active Now Playing entry, and distinct from saved playlists, listening history, or favorites.
_Avoid_: Saved playlist, listening history, library

**Now Playing**:
The single music file currently active in the playback state and represented by its current position in the live Playback List. It cannot be removed while active; if earlier entries are removed, Now Playing's list position changes without interrupting playback.
_Avoid_: Selected track, detached current item

**Playback State**:
The runtime playback condition reported by the player: idle, playing, paused, stopped, or unsupported. Idle has no Now Playing entry; stopped retains a Now Playing entry without audio output; unsupported records a failed playback attempt.
_Avoid_: Player mode, transport mode

**Folder Add**:
The synchronous action of appending every Candidate Music File under a selected library folder to the Playback List. It includes nested folders, skips non-candidate files, and uses a stable relative-path order without background progress tracking in the MVP.
_Avoid_: Import, sync, scan

**Candidate Music File**:
A local file inside the Music Library Root whose extension is accepted by the MVP for browsing and adding to the Playback List: flac, wav, aiff, aif, or m4a. Candidate files still require playback-time validation before they become Supported Music Files, including validating that m4a content is suitable for the MVP; DSD/DoP formats are not candidates.
_Avoid_: Playable file, imported file, indexed file

**Supported Music File**:
A local lossless or PCM audio file inside the Music Library Root that the macOS audio stack can decode without third-party decoder fallback. Lossy codecs, including AAC content inside an m4a container, are outside the playable domain for the MVP.
_Avoid_: Track, song, media asset

**File Identity**:
The display identity of a Candidate Music File, based on its file name or path relative to the Music Library Root. Embedded title, artist, album, artwork tags, and CUE sheet track boundaries are not part of the MVP domain.
_Avoid_: Track metadata, album metadata, artist catalog

**Playback Output Device**:
The selected local audio endpoint used for playback. The active device is required before playback, is part of runtime playback state, is not persisted by the MVP, and may be changed at runtime by the operator.
_Avoid_: System output, speaker, sink

**Output Device List**:
The Operator Remote list of local audio output endpoints that can be selected for playback. Format support is validated when playback is attempted rather than fully modeled in the list.
_Avoid_: Capability matrix, device profile

**Output Device Switch**:
The operator action of changing the Playback Output Device during a server run. If playback is active, the current stream is stopped and the current file is restarted on the new device when supported.
_Avoid_: Seamless handoff, audio routing

**Operator Remote**:
The trusted mobile-first HTTP control surface used by an operator to manage playback, the Playback List, and playback output. It has no user accounts, roles, sessions, or multi-user conflict model in the MVP.
_Avoid_: Admin portal, user app, account

**Runtime Info**:
The read-only Operator Remote display of the current server address, Music Library Root, and selected Playback Output Device. It confirms runtime configuration but does not allow changing startup configuration.
_Avoid_: Settings, preferences, configuration editor

**Remote API**:
The REST/JSON HTTP surface used by the Operator Remote to issue commands and poll playback state. Built-in HTTPS, push updates through WebSocket, and server-sent events are outside the MVP.
_Avoid_: Streaming API, realtime bus, socket control

**Remote Bind Address**:
The network address on which the Operator Remote is exposed. Local-only access is the default, and broader network exposure must be selected explicitly by the operator.
_Avoid_: Public URL, login endpoint

**Server CLI**:
The command-line surface for starting the foreground HTTP server process and listing local audio output devices. It is not a playback-control, library-management, background-service, packaged native-app, or power-management surface in the MVP.
_Avoid_: Desktop app, command player, shell remote

**Previous Command**:
The playback command that either restarts the current music file or moves to the previous Playback List entry. At three seconds or later into the current file it restarts that file; before three seconds it moves to the previous list entry when one exists.
_Avoid_: Rewind, seek, back

**Playback List End**:
The playback state reached when there is no next Playback List entry after the current music file finishes or the Next command is used. Playback stops and the Playback List remains intact; looping, shuffle, fast-forward, rewind, seeking, and gapless playback are outside the MVP.
_Avoid_: Repeat, autoplay, shuffle

**Playback List Selection**:
The operator action of choosing an existing Playback List entry to become Now Playing. It starts the selected file from the beginning when supported by the current Playback Output Device and is separate from adding music from the Library Browser.
_Avoid_: Search play, library play, direct library play

**Paused Playback**:
The playback state where the current music file, playback position, output device, and configured source format are retained while audio output is suspended. Resuming playback continues from the retained position.
_Avoid_: Stop, idle, reset

**Play Command**:
The playback command that starts, resumes, or retries playback. It resumes Paused Playback from the retained position, starts the first Playback List entry when there is no Now Playing entry, restarts the retained Now Playing entry from the beginning after playback has stopped, and retries the retained Now Playing entry after Unsupported Playback.
_Avoid_: Start over, resume button

**Read-Only Progress**:
The Operator Remote display of the current file name, playback state, elapsed time, and total duration when known. Unknown duration does not block playback, and progress display does not allow seeking or dragging the playback position in the MVP.
_Avoid_: Seek bar, scrubber, timeline control

**Library Browser**:
The Operator Remote view of folders and Candidate Music Files inside the Music Library Root, addressed by paths relative to that root. It reads the filesystem on demand, allows folder navigation and Playback List adds, does not follow symbolic links outside the library boundary, and does not expose metadata search, artwork, cache scanning, or files outside the library boundary.
_Avoid_: File picker, media catalog, search
