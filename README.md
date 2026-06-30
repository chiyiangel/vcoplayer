# VCO Player

VCO Player is a macOS-only headless music player. The first MVP focuses on Bit Perfect local playback through Apple CoreAudio and remote control from a mobile-first web UI.

## MVP Scope

- Server runs as a foreground Swift CLI process. There is no native macOS GUI, menu bar app, LaunchAgent, packaged app, or power-management integration in the MVP.
- Backend is a Swift Package Manager executable named `vcoplayer`, implemented in Swift with Apple CoreAudio, `swift-argument-parser`, and a SwiftNIO-based HTTP framework such as Hummingbird.
- Frontend lives in `web/` as a separate Vite React TypeScript app using npm. The backend does not serve frontend static assets.
- Runtime uses two development processes: the Swift API server and the Vite dev server. Vite proxies `/api/*` to the backend.
- UI text is Chinese in the MVP. API names, code types, and domain terms use English.

## Audio Principles

Bit Perfect Playback is the primary product constraint. The player must not apply software volume, EQ, DSP, system mixing, sample-rate conversion, bit-depth conversion, automatic device fallback, or lossy fallback decoding.

Playback fails explicitly when the selected output device or audio path cannot preserve the source format. The web UI should show an operator-readable failure reason, while the CLI should print more detailed diagnostics.

Supported candidate file extensions for the MVP are:

- `.flac`
- `.wav`
- `.aiff`
- `.aif`
- `.m4a` for ALAC only

AAC-in-M4A, MP3, AAC, DSD/DoP, CUE sheet splitting, metadata cataloging, album artwork, search, shuffle, repeat, seek, fast-forward, rewind, and gapless playback are outside the MVP.

## Music Library

The server starts with a single Music Library Root:

```sh
swift run vcoplayer serve --library ~/Music --host 127.0.0.1 --port 8080
```

The Operator Remote can browse only inside that root. API requests use paths relative to the root; the backend resolves and validates real paths so `..` traversal and symlinks outside the root are rejected.

The library is read on demand. There is no import step, metadata database, scan cache, saved playlist, listening history, or persistence in the MVP.

Folder add behavior:

- Recursively collects candidate music files.
- Skips non-candidate files.
- Sorts by stable relative path order.
- Appends synchronously to the Playback List.

## Playback Model

The Playback List is an in-memory ordered list for the current server run. It may contain repeated files; each entry has a runtime item ID so duplicate paths can be selected or deleted independently. The list is cleared when the server exits.

Rules:

- `play` resumes paused playback, starts the first list entry when idle, restarts the retained Now Playing entry after stopped, and retries after unsupported playback.
- `pause` keeps the current file, position, output device, and configured source format.
- `next` moves to the next live Playback List entry; at the end, playback stops and the list remains intact.
- `previous` restarts the current file at or after 3 seconds; before 3 seconds, it moves to the previous live list entry if one exists.
- Selecting any Playback List entry starts that entry from the beginning.
- Deleting entries and clearing the list are allowed, but the active Now Playing entry cannot be removed or interrupted.
- There is no software volume control. Volume is handled outside the player.

The web UI displays read-only progress: current file, state, elapsed time, and duration when known. Unknown duration does not block playback.

## Output Devices

Playback requires a selected local CoreAudio output device. Use `swift run vcoplayer devices` to list devices, then select one in the Operator Remote after the server starts. Device choice is runtime-only and is not persisted.

When the output device changes during active playback, the current stream stops and the current file restarts from the beginning on the new device if supported. If the new device cannot preserve Bit Perfect Playback for the file, playback enters the unsupported state.

The web UI lists selectable local output devices. Detailed format support is validated when playback is attempted rather than modeled as a full capability matrix.

## HTTP API Shape

The backend exposes REST/JSON under `/api/*`. It does not serve frontend assets, does not enable CORS by default, does not provide built-in HTTPS, and does not use WebSocket or server-sent events in the MVP. The Vite development server proxies `/api` to `http://127.0.0.1:8080`.

`PlayerStatus` is the Remote API status shape returned by `GET /api/status` and by successful mutating commands:

- `playbackState`: `idle`, `playing`, `paused`, `stopped`, or `unsupported`.
- `nowPlaying`: relative path for the current Now Playing file, or `null`.
- `nowPlayingItemId`: runtime Playback List item ID for the current Now Playing entry, or `null`.
- `playbackList`: ordered array of `{ "itemId": "...", "path": "..." }` entries.
- `selectedOutputDevice`: `{ "id": "...", "name": "..." }`, or `null`.
- `progress`: `{ "elapsedSeconds": 0, "durationSeconds": 123.4 }`, with `durationSeconds` allowed to be `null`.
- `failureReason`: operator-readable failure text, or `null`.
- `runtimeInfo`: `{ "musicLibraryRoot": "...", "serverHost": "...", "serverPort": 8080 }`.

Query endpoints:

| Endpoint | Response | Notes |
| --- | --- | --- |
| `GET /api/status` | `PlayerStatus` | Current playback state, Now Playing, Playback List, selected output device, progress, runtime info, and failure reason. |
| `GET /api/devices` | `OutputDevice[]` | Selectable local CoreAudio output devices. |
| `GET /api/library?path=...` | `LibraryDirectory` | Browse a path relative to the Music Library Root. Omit `path` for the root. |

Command endpoints:

| Endpoint | Body | Response |
| --- | --- | --- |
| `POST /api/play` | none | `PlayerStatus` |
| `POST /api/pause` | none | `PlayerStatus` |
| `POST /api/next` | none | `PlayerStatus` |
| `POST /api/previous` | none | `PlayerStatus` |
| `POST /api/devices/select` | `{ "deviceId": "coreaudio:..." }` | `PlayerStatus` |
| `POST /api/playback-list/files` | `{ "path": "Album/Track.flac" }` | `PlayerStatus` |
| `POST /api/playback-list/folders` | `{ "path": "Album" }` | `PlayerStatus` |
| `POST /api/playback-list/select` | `{ "itemId": "..." }` | `PlayerStatus` |
| `POST /api/playback-list/delete` | `{ "itemId": "..." }` | `PlayerStatus` |
| `POST /api/playback-list/clear` | none | `PlayerStatus` |

Request errors return JSON shaped as `{ "code": "...", "message": "..." }`. Unsupported playback is a valid player state and returns status with `playbackState: "unsupported"` rather than a transport-level HTTP error.

The Operator Remote loads `/api/status` and `/api/devices` on first render. Command responses update UI state immediately; the MVP has no background polling or realtime push.

## Frontend

The `web/` app is mobile-first and uses two main views:

- `播放`: Now Playing, read-only progress, playback controls, output device selection, runtime info, and Playback List management.
- `资料库`: folder navigation inside the Music Library Root, with actions to add a folder or single file to the Playback List.

The MVP does not include user accounts, roles, sessions, multi-user conflict handling, i18n, or theme switching.

## Development

Repository structure:

```text
.
├── Package.swift
├── Sources/
│   ├── VCOPlayerCore/
│   └── vcoplayer/
├── Tests/
│   └── vcoplayerBackendTests/
├── web/
│   ├── package.json
│   └── src/
├── CONTEXT.md
└── docs/
    └── adr/
```

Backend:

```sh
swift run vcoplayer serve --library ~/Music --host 127.0.0.1 --port 8080
swift run vcoplayer devices
```

Frontend:

```sh
cd web
npm install
npm run dev
```

Open the Operator Remote at `http://127.0.0.1:5173/`. Keep both processes running. The proxy in `web/vite.config.ts` forwards `/api` requests from Vite to the backend at `http://127.0.0.1:8080`.

Phone testing on the local network:

```sh
ipconfig getifaddr en0
cd web
npm run dev -- --host 0.0.0.0
```

With the backend still running on `127.0.0.1:8080`, open `http://<mac-lan-ip>:5173/` on a phone connected to the same Wi-Fi network. The phone talks to Vite, and Vite forwards `/api` to the local backend process on the Mac. If you need to call the Remote API directly from another device, start the backend with a LAN bind instead:

```sh
swift run vcoplayer serve --library ~/Music --host 0.0.0.0 --port 8080
```

The backend defaults to local-only access, and macOS firewall settings can still block LAN testing.

## Testing

Automated verification:

```sh
swift run vcoplayerBackendTests
cd web
npm test
npm run lint
npm run build
```

Backend automated tests currently run through `swift run vcoplayerBackendTests` because the available Command Line Tools Swift installation does not include XCTest. These tests cover public behavior such as Remote API status, Music Library Root validation, Server CLI parsing, Playback List commands, output-device selection, and README/API documentation drift. Frontend automated tests use Vitest for API client behavior, state logic, and key component interactions.

Manual MVP Verification Checklist:

- real CoreAudio output: start the backend, select a built-in Mac output device in the Operator Remote, add a known-good WAV, FLAC, AIFF, or ALAC file from the Music Library Root to the Playback List, and verify play, pause, next, previous, elapsed time, duration, Now Playing, and no unexpected failure reason.
- USB DAC playback: connect a USB DAC, confirm it appears in `swift run vcoplayer devices` and `GET /api/devices`, select it in the Operator Remote, then verify Playback List playback starts on that device without falling back to another output.
- Bit Perfect failure behavior: use a known unsupported file or output path such as AAC-in-M4A or a device/format combination that cannot preserve the source format; verify playback enters `unsupported`, the Operator Remote shows the failure reason, and no software conversion or fallback output is used.
- output-device switching: while a supported file is playing, switch to another selectable output device and verify the current Now Playing file restarts from the beginning on the new device; if the new device cannot preserve Bit Perfect Playback, verify the state becomes `unsupported`.
- device-busy failures: make a selected device unavailable or busy, attempt playback or switch to it, and verify `failureReason` is visible, `selectedOutputDevice` reflects the attempted device, and the player does not silently choose another output.
- mobile layout: run the Phone testing workflow, open the Operator Remote on a phone, and verify the `播放` and `资料库` views fit without overlapping controls, allow browsing the Music Library Root, adding folders/files, selecting/deleting Playback List entries, clearing the Playback List, selecting an output device, and reading any Bit Perfect Playback failure reason.

## Decision Records

- [ADR 0001: Bit Perfect Playback over fallback output](docs/adr/0001-bit-perfect-playback-over-fallback-output.md)
- [ADR 0002: Apple CoreAudio-only audio stack](docs/adr/0002-apple-coreaudio-only-audio-stack.md)
