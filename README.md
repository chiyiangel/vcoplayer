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

Playback requires a selected local CoreAudio output device. The initial device may be provided by CLI, and the Operator Remote can change it at runtime. Device choice is not persisted.

When the output device changes during active playback, the current stream stops and the current file restarts from the beginning on the new device if supported. If the new device cannot preserve Bit Perfect Playback for the file, playback enters the unsupported state.

The web UI lists selectable local output devices. Detailed format support is validated when playback is attempted rather than modeled as a full capability matrix.

## HTTP API Shape

The backend exposes REST/JSON under `/api/*`. It does not serve frontend assets, does not enable CORS by default, does not provide built-in HTTPS, and does not use WebSocket or server-sent events in the MVP.

Expected query endpoints:

- `GET /api/status` returns playback state, Now Playing, the full Playback List, current device, read-only progress, runtime info, and any failure reason.
- `GET /api/devices` lists local output devices.
- `GET /api/library?path=...` browses a relative library path.

Expected command endpoints:

- `POST /api/play`
- `POST /api/pause`
- `POST /api/next`
- `POST /api/previous`
- `POST /api/devices/select`
- `POST /api/playback-list/files`
- `POST /api/playback-list/folders`
- `POST /api/playback-list/items/{itemId}/play`
- `DELETE /api/playback-list/items/{itemId}`
- `DELETE /api/playback-list`

Mutating API calls return the latest `PlayerStatus` on success. Request errors return JSON shaped as `{ "code": "...", "message": "..." }`. Unsupported playback is a valid player state and should return status with `playbackState: "unsupported"` rather than a transport-level HTTP error.

The frontend polls `/api/status` once per second. Command responses update UI state immediately.

## Frontend

The `web/` app is mobile-first and uses two main views:

- `播放`: Now Playing, read-only progress, playback controls, output device selection, runtime info, and Playback List management.
- `资料库`: folder navigation inside the Music Library Root, with actions to add a folder or single file to the Playback List.

The MVP does not include user accounts, roles, sessions, multi-user conflict handling, i18n, or theme switching.

## Development

Planned repository structure:

```text
.
├── Package.swift
├── Sources/
│   └── vcoplayer/
├── Tests/
│   └── vcoplayerTests/
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

For phone testing on the local network, run the Vite dev server with a LAN bind such as `--host 0.0.0.0` and start the backend with an explicit LAN bind. The backend defaults to local-only access.

## Testing

- Backend automated tests currently run through `swift run vcoplayerBackendTests` because the available Command Line Tools Swift installation does not include XCTest. These tests cover public behavior such as Remote API status, Music Library Root validation, and Server CLI parsing.
- Frontend automated tests use Vitest for API client behavior, state logic, and key component interactions.
- Real CoreAudio output, USB DAC behavior, Bit Perfect playback, device switching, and mobile layout are manually verified for the MVP.

## Decision Records

- [ADR 0001: Bit Perfect Playback over fallback output](docs/adr/0001-bit-perfect-playback-over-fallback-output.md)
- [ADR 0002: Apple CoreAudio-only audio stack](docs/adr/0002-apple-coreaudio-only-audio-stack.md)
