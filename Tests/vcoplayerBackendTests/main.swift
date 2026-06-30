import Foundation
import HummingbirdTesting
import NIOCore
import VCOPlayerCore

enum TestFailure: Error, CustomStringConvertible {
    case expectationFailed(String)

    var description: String {
        switch self {
        case .expectationFailed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure.expectationFailed(message)
    }
}

struct StubOutputDeviceProvider: OutputDeviceProviding {
    let devices: [OutputDevice]

    func outputDevices() throws -> [OutputDevice] {
        self.devices
    }
}

actor StubPlaybackController: PlaybackControlling {
    private var startResults: [PlaybackStartResult]
    private let pauseResult: PlaybackPauseResult

    init(
        startResults: [PlaybackStartResult],
        pauseResult: PlaybackPauseResult = PlaybackPauseResult(progress: PlaybackProgress(elapsedSeconds: 0, durationSeconds: nil))
    ) {
        self.startResults = startResults
        self.pauseResult = pauseResult
    }

    func start(_ request: PlaybackStartRequest) async -> PlaybackStartResult {
        self.startResults.isEmpty
            ? .playing(PlaybackProgress(elapsedSeconds: 0, durationSeconds: nil))
            : self.startResults.removeFirst()
    }

    func pause() async -> PlaybackPauseResult {
        self.pauseResult
    }
}

@main
struct BackendTestRunner {
    static func main() async {
        do {
            try await statusReturnsIdlePlayerStatusForValidMusicLibraryRoot()
            print("PASS statusReturnsIdlePlayerStatusForValidMusicLibraryRoot")
            try await playCommandStartsFirstPlaybackListEntryWhenIdleWithSelectedOutputDevice()
            print("PASS playCommandStartsFirstPlaybackListEntryWhenIdleWithSelectedOutputDevice")
            try await pauseCommandRetainsNowPlayingDeviceAndProgressThenPlayResumes()
            print("PASS pauseCommandRetainsNowPlayingDeviceAndProgressThenPlayResumes")
            try await playCommandReportsUnsupportedPlaybackWhenOutputDeviceIsMissing()
            print("PASS playCommandReportsUnsupportedPlaybackWhenOutputDeviceIsMissing")
            try await outputDeviceSelectionClearsMissingDeviceFailureBeforePlaybackStarts()
            print("PASS outputDeviceSelectionClearsMissingDeviceFailureBeforePlaybackStarts")
            try await playCommandReportsUnsupportedPlaybackFromPlaybackTimeValidation()
            print("PASS playCommandReportsUnsupportedPlaybackFromPlaybackTimeValidation")
            try await devicesEndpointReturnsSelectableOutputDevices()
            print("PASS devicesEndpointReturnsSelectableOutputDevices")
            try await selectOutputDeviceUpdatesPlayerStatusForCurrentServerRun()
            print("PASS selectOutputDeviceUpdatesPlayerStatusForCurrentServerRun")
            try await selectedOutputDeviceIsNotPersistedAcrossServerRuns()
            print("PASS selectedOutputDeviceIsNotPersistedAcrossServerRuns")
            try devicesCommandFormatsOutputDeviceListFromProvider()
            print("PASS devicesCommandFormatsOutputDeviceListFromProvider")
            try await addCandidateMusicFileAppendsPlaybackListItem()
            print("PASS addCandidateMusicFileAppendsPlaybackListItem")
            try await addCandidateMusicFileCreatesDistinctRuntimeItemsForDuplicates()
            print("PASS addCandidateMusicFileCreatesDistinctRuntimeItemsForDuplicates")
            try await folderAddAppendsNestedCandidateMusicFilesInStableRelativePathOrder()
            print("PASS folderAddAppendsNestedCandidateMusicFilesInStableRelativePathOrder")
            try await libraryBrowserReturnsRootFoldersAndCandidateMusicFiles()
            print("PASS libraryBrowserReturnsRootFoldersAndCandidateMusicFiles")
            try await libraryBrowserAcceptsRootRelativeSubfolderPaths()
            print("PASS libraryBrowserAcceptsRootRelativeSubfolderPaths")
            try await libraryBrowserLimitsCandidateMusicFilesToMVPFormats()
            print("PASS libraryBrowserLimitsCandidateMusicFilesToMVPFormats")
            try await libraryBrowserRejectsTraversalAndAbsolutePathsWithRequestErrors()
            print("PASS libraryBrowserRejectsTraversalAndAbsolutePathsWithRequestErrors")
            try await libraryBrowserRejectsSymlinkedDirectoriesOutsideMusicLibraryRoot()
            print("PASS libraryBrowserRejectsSymlinkedDirectoriesOutsideMusicLibraryRoot")
            try await libraryBrowserDoesNotExposeSymlinkedEntriesOutsideMusicLibraryRoot()
            print("PASS libraryBrowserDoesNotExposeSymlinkedEntriesOutsideMusicLibraryRoot")
            try rejectsInvalidMusicLibraryRoot()
            print("PASS rejectsInvalidMusicLibraryRoot")
            try serveCommandUsesLocalOnlyDefaults()
            print("PASS serveCommandUsesLocalOnlyDefaults")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }

    static func playCommandStartsFirstPlaybackListEntryWhenIdleWithSelectedOutputDevice() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [outputDevice]),
            playbackController: StubPlaybackController(
                startResults: [
                    .playing(
                        PlaybackProgress(elapsedSeconds: 0, durationSeconds: 182.5)
                    ),
                ]
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"path":"Intro.flac"}"#)
            ) { response in
                try expect(response.status == .ok, "expected file add to succeed")
            }

            try await client.execute(
                uri: "/api/devices/select",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            ) { response in
                try expect(response.status == .ok, "expected device select to succeed")
            }

            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected HTTP 200 from Play Command")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .playing, "expected Play Command to enter playing state")
                try expect(status.nowPlaying == "Intro.flac", "expected first Playback List entry to become Now Playing")
                try expect(status.progress == PlaybackProgress(elapsedSeconds: 0, durationSeconds: 182.5), "expected read-only progress from playback path")
                try expect(status.failureReason == nil, "expected successful Play Command to clear Playback Failure Reason")
            }
        }
    }

    static func pauseCommandRetainsNowPlayingDeviceAndProgressThenPlayResumes() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [outputDevice]),
            playbackController: StubPlaybackController(
                startResults: [
                    .playing(PlaybackProgress(elapsedSeconds: 0, durationSeconds: 182.5)),
                    .playing(PlaybackProgress(elapsedSeconds: 37, durationSeconds: 182.5)),
                ],
                pauseResult: PlaybackPauseResult(
                    progress: PlaybackProgress(elapsedSeconds: 37, durationSeconds: 182.5)
                )
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"path":"Intro.flac"}"#)
            ) { response in
                try expect(response.status == .ok, "expected file add to succeed")
            }
            try await client.execute(
                uri: "/api/devices/select",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            ) { response in
                try expect(response.status == .ok, "expected device select to succeed")
            }
            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected Play Command to succeed")
            }

            try await client.execute(uri: "/api/pause", method: .post) { response in
                try expect(response.status == .ok, "expected HTTP 200 from Pause Command")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .paused, "expected Pause Command to enter Paused Playback")
                try expect(status.nowPlaying == "Intro.flac", "expected Pause Command to retain Now Playing")
                try expect(status.selectedOutputDevice == outputDevice, "expected Pause Command to retain selected Playback Output Device")
                try expect(status.progress == PlaybackProgress(elapsedSeconds: 37, durationSeconds: 182.5), "expected Pause Command to retain playback position")
            }

            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected Play Command to resume Paused Playback")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .playing, "expected Play Command to resume playing")
                try expect(status.nowPlaying == "Intro.flac", "expected Play Command to keep Now Playing while resuming")
                try expect(status.progress == PlaybackProgress(elapsedSeconds: 37, durationSeconds: 182.5), "expected Play Command to resume from retained position")
            }
        }
    }

    static func playCommandReportsUnsupportedPlaybackWhenOutputDeviceIsMissing() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            playbackController: StubPlaybackController(startResults: [
                .playing(PlaybackProgress(elapsedSeconds: 0, durationSeconds: 182.5)),
            ])
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"path":"Intro.flac"}"#)
            ) { response in
                try expect(response.status == .ok, "expected file add to succeed")
            }

            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected Unsupported Playback to be represented as PlayerStatus")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .unsupported, "expected missing output device to produce Unsupported Playback")
                try expect(status.nowPlaying == nil, "expected missing output device not to start Now Playing")
                try expect(status.failureReason == "Playback requires a selected Playback Output Device.", "expected operator-visible missing-device failure reason")
            }
        }
    }

    static func outputDeviceSelectionClearsMissingDeviceFailureBeforePlaybackStarts() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [outputDevice]),
            playbackController: StubPlaybackController(startResults: [
                .playing(PlaybackProgress(elapsedSeconds: 0, durationSeconds: 182.5)),
            ])
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"path":"Intro.flac"}"#)
            ) { response in
                try expect(response.status == .ok, "expected file add to succeed")
            }
            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected missing device failure to be represented as PlayerStatus")
            }

            try await client.execute(
                uri: "/api/devices/select",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            ) { response in
                try expect(response.status == .ok, "expected device select to succeed")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .idle, "expected selecting a missing Playback Output Device to return to idle before playback starts")
                try expect(status.selectedOutputDevice == outputDevice, "expected selected Playback Output Device")
                try expect(status.failureReason == nil, "expected missing-device failure to be cleared once a device is selected")
            }
        }
    }

    static func playCommandReportsUnsupportedPlaybackFromPlaybackTimeValidation() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Lossy.m4a"))
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [outputDevice]),
            playbackController: StubPlaybackController(startResults: [
                .unsupported("Unsupported Playback: lossy m4a content cannot preserve Bit Perfect Playback."),
            ])
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"path":"Lossy.m4a"}"#)
            ) { response in
                try expect(response.status == .ok, "expected m4a Candidate Music File to be addable before playback validation")
            }
            try await client.execute(
                uri: "/api/devices/select",
                method: .post,
                body: ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            ) { response in
                try expect(response.status == .ok, "expected device select to succeed")
            }

            try await client.execute(uri: "/api/play", method: .post) { response in
                try expect(response.status == .ok, "expected Unsupported Playback to be represented as PlayerStatus")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .unsupported, "expected playback-time validation to produce Unsupported Playback")
                try expect(status.nowPlaying == "Lossy.m4a", "expected failed playback attempt to retain Now Playing for retry")
                try expect(status.failureReason == "Unsupported Playback: lossy m4a content cannot preserve Bit Perfect Playback.", "expected playback-time validation failure reason")
            }
        }
    }

    static func libraryBrowserLimitsCandidateMusicFilesToMVPFormats() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        for name in ["01.flac", "02.wav", "03.aiff", "04.aif", "05.m4a", "ignored.mp3", "ignored.aac", "ignored.dsf"] {
            try Data().write(to: libraryRoot.appendingPathComponent(name))
        }

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/library", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/library")

                let body = String(buffer: response.body)
                let directory = try JSONDecoder().decode(LibraryDirectory.self, from: Data(body.utf8))
                try expect(directory.files.map(\.name) == ["01.flac", "02.wav", "03.aiff", "04.aif", "05.m4a"], "expected only MVP Candidate Music File formats")
            }
        }
    }

    static func devicesCommandFormatsOutputDeviceListFromProvider() throws {
        let output = try DevicesCommand.output(
            deviceProvider: StubOutputDeviceProvider(devices: [
                OutputDevice(id: "coreaudio:41", name: "USB DAC"),
                OutputDevice(id: "coreaudio:55", name: "Built-in Output"),
            ])
        )

        try expect(
            output == """
            coreaudio:41\tUSB DAC
            coreaudio:55\tBuilt-in Output
            """,
            "expected Server CLI devices output to include stable identifiers and names"
        )
    }

    static func selectedOutputDeviceIsNotPersistedAcrossServerRuns() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")
        let outputDeviceProvider = StubOutputDeviceProvider(devices: [outputDevice])

        let firstApp = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: outputDeviceProvider
        )

        try await firstApp.test(.router) { client in
            let body = ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            try await client.execute(uri: "/api/devices/select", method: .post, body: body) { response in
                try expect(response.status == .ok, "expected device select to succeed")
            }
        }

        let nextApp = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: outputDeviceProvider
        )

        try await nextApp.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/status")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.selectedOutputDevice == nil, "expected Playback Output Device selection to be runtime-only")
            }
        }
    }

    static func selectOutputDeviceUpdatesPlayerStatusForCurrentServerRun() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let outputDevice = OutputDevice(id: "coreaudio:41", name: "USB DAC")

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [outputDevice])
        )

        try await app.test(.router) { client in
            let body = ByteBufferAllocator().buffer(string: #"{"deviceId":"coreaudio:41"}"#)
            try await client.execute(uri: "/api/devices/select", method: .post, body: body) { response in
                try expect(response.status == .ok, "expected HTTP 200 from device select endpoint")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.selectedOutputDevice == outputDevice, "expected selected Playback Output Device in command response")
            }

            try await client.execute(uri: "/api/status", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/status")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.selectedOutputDevice == outputDevice, "expected selected Playback Output Device to be runtime state")
            }
        }
    }

    static func devicesEndpointReturnsSelectableOutputDevices() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0,
            outputDeviceProvider: StubOutputDeviceProvider(devices: [
                OutputDevice(id: "coreaudio:41", name: "USB DAC"),
                OutputDevice(id: "coreaudio:55", name: "Built-in Output"),
            ])
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/devices", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/devices")

                let body = String(buffer: response.body)
                let devices = try JSONDecoder().decode([OutputDevice].self, from: Data(body.utf8))
                try expect(
                    devices == [
                        OutputDevice(id: "coreaudio:41", name: "USB DAC"),
                        OutputDevice(id: "coreaudio:55", name: "Built-in Output"),
                    ],
                    "expected selectable Playback Output Devices from provider"
                )
            }
        }
    }

    static func folderAddAppendsNestedCandidateMusicFilesInStableRelativePathOrder() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let albumURL = libraryRoot.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: albumURL.appendingPathComponent("Disc 1"), withIntermediateDirectories: true)
        try Data().write(to: albumURL.appendingPathComponent("Beta.wav"))
        try Data().write(to: albumURL.appendingPathComponent("Alpha.aif"))
        try Data().write(to: albumURL.appendingPathComponent("Notes.txt"))
        try Data().write(to: albumURL.appendingPathComponent("Disc 1").appendingPathComponent("01.flac"))
        try Data().write(to: albumURL.appendingPathComponent("Disc 1").appendingPathComponent("Cover.jpg"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            let body = ByteBufferAllocator().buffer(string: #"{"path":"Album"}"#)
            try await client.execute(uri: "/api/playback-list/folders", method: .post, body: body) { response in
                try expect(response.status == .ok, "expected HTTP 200 from Folder Add endpoint")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(
                    status.playbackList.map(\.path) == [
                        "Album/Alpha.aif",
                        "Album/Beta.wav",
                        "Album/Disc 1/01.flac",
                    ],
                    "expected Folder Add to append nested Candidate Music Files in stable relative-path order"
                )
            }
        }
    }

    static func addCandidateMusicFileCreatesDistinctRuntimeItemsForDuplicates() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Repeat.m4a"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            let body = #"{"path":"Repeat.m4a"}"#
            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: body)
            ) { response in
                try expect(response.status == .ok, "expected first duplicate add to succeed")
            }

            try await client.execute(
                uri: "/api/playback-list/files",
                method: .post,
                body: ByteBufferAllocator().buffer(string: body)
            ) { response in
                try expect(response.status == .ok, "expected second duplicate add to succeed")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackList.map(\.path) == ["Repeat.m4a", "Repeat.m4a"], "expected duplicate file paths to be retained")
                try expect(status.playbackList[0].itemId != status.playbackList[1].itemId, "expected duplicate entries to have distinct runtime identities")
            }
        }
    }

    static func addCandidateMusicFileAppendsPlaybackListItem() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            let body = ByteBufferAllocator().buffer(string: #"{"path":"Intro.flac"}"#)
            try await client.execute(uri: "/api/playback-list/files", method: .post, body: body) { response in
                try expect(response.status == .ok, "expected HTTP 200 from file add endpoint")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackList.count == 1, "expected one Playback List entry")
                try expect(status.playbackList[0].path == "Intro.flac", "expected Playback List entry to use root-relative file path")
                try expect(!status.playbackList[0].itemId.isEmpty, "expected Playback List entry to have runtime identity")
            }
        }
    }

    static func libraryBrowserDoesNotExposeSymlinkedEntriesOutsideMusicLibraryRoot() async throws {
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryRoot = temporaryRoot.appendingPathComponent("Music", isDirectory: true)
        let outsideRoot = temporaryRoot.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try Data().write(to: outsideRoot.appendingPathComponent("Outside.flac"))
        try FileManager.default.createSymbolicLink(
            at: libraryRoot.appendingPathComponent("Escape"),
            withDestinationURL: outsideRoot
        )
        try FileManager.default.createSymbolicLink(
            at: libraryRoot.appendingPathComponent("Outside.flac"),
            withDestinationURL: outsideRoot.appendingPathComponent("Outside.flac")
        )

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/library", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 for Music Library Root")

                let body = String(buffer: response.body)
                let directory = try JSONDecoder().decode(LibraryDirectory.self, from: Data(body.utf8))
                try expect(directory.folders.isEmpty, "expected outside symlink folder to be hidden")
                try expect(directory.files.isEmpty, "expected outside symlink file to be hidden")
            }
        }
    }

    static func libraryBrowserRejectsSymlinkedDirectoriesOutsideMusicLibraryRoot() async throws {
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryRoot = temporaryRoot.appendingPathComponent("Music", isDirectory: true)
        let outsideRoot = temporaryRoot.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try Data().write(to: outsideRoot.appendingPathComponent("Leaked.flac"))
        try FileManager.default.createSymbolicLink(
            at: libraryRoot.appendingPathComponent("Escape"),
            withDestinationURL: outsideRoot
        )

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/library?path=Escape", method: .get) { response in
                try expect(response.status == .badRequest, "expected HTTP 400 for symlink outside Music Library Root")

                let body = String(buffer: response.body)
                let requestError = try JSONDecoder().decode(RequestError.self, from: Data(body.utf8))
                try expect(requestError.code == "invalid_library_path", "expected structured request error code")
            }
        }
    }

    static func libraryBrowserRejectsTraversalAndAbsolutePathsWithRequestErrors() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            for path in ["../outside", "/tmp"] {
                try await client.execute(uri: "/api/library?path=\(path)", method: .get) { response in
                    try expect(response.status == .badRequest, "expected HTTP 400 for invalid library path \(path)")

                    let body = String(buffer: response.body)
                    let requestError = try JSONDecoder().decode(RequestError.self, from: Data(body.utf8))
                    try expect(requestError.code == "invalid_library_path", "expected structured request error code")
                    try expect(!requestError.message.isEmpty, "expected structured request error message")
                }
            }
        }
    }

    static func libraryBrowserAcceptsRootRelativeSubfolderPaths() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let albumURL = libraryRoot.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: albumURL.appendingPathComponent("Disc 1"), withIntermediateDirectories: true)
        try Data().write(to: albumURL.appendingPathComponent("Track 01.wav"))
        try Data().write(to: albumURL.appendingPathComponent("Cover.jpg"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/library?path=Album", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/library for a subfolder")

                let body = String(buffer: response.body)
                let directory = try JSONDecoder().decode(LibraryDirectory.self, from: Data(body.utf8))
                try expect(directory.path == "Album", "expected requested root-relative path")
                try expect(directory.folders == [LibraryFolder(name: "Disc 1", path: "Album/Disc 1")], "expected child folder path to stay root-relative")
                try expect(directory.files == [LibraryFile(name: "Track 01.wav", path: "Album/Track 01.wav")], "expected subfolder Candidate Music File")
            }
        }
    }

    static func statusReturnsIdlePlayerStatusForValidMusicLibraryRoot() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/status")

                let body = String(buffer: response.body)
                let status = try JSONDecoder().decode(PlayerStatus.self, from: Data(body.utf8))
                try expect(status.playbackState == .idle, "expected idle Playback State")
                try expect(status.nowPlaying == nil, "expected no Now Playing entry")
                try expect(status.playbackList.isEmpty, "expected empty Playback List")
                try expect(status.selectedOutputDevice == nil, "expected no selected Playback Output Device")
                try expect(status.failureReason == nil, "expected no Playback Failure Reason")
                try expect(status.runtimeInfo.musicLibraryRoot == libraryRoot.path, "expected Runtime Info to include Music Library Root")
                try expect(status.runtimeInfo.serverHost == "127.0.0.1", "expected Runtime Info to include server host")
                try expect(status.runtimeInfo.serverPort == 0, "expected Runtime Info to include server port")
            }
        }
    }

    static func libraryBrowserReturnsRootFoldersAndCandidateMusicFiles() async throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("Album"), withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("Intro.flac"))
        try Data().write(to: libraryRoot.appendingPathComponent("Notes.txt"))

        let app = try buildApplication(
            libraryRoot: libraryRoot,
            host: "127.0.0.1",
            port: 0
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/library", method: .get) { response in
                try expect(response.status == .ok, "expected HTTP 200 from /api/library")

                let body = String(buffer: response.body)
                let directory = try JSONDecoder().decode(LibraryDirectory.self, from: Data(body.utf8))
                try expect(directory.path == "", "expected root-relative path for Music Library Root")
                try expect(directory.folders == [LibraryFolder(name: "Album", path: "Album")], "expected root folder to be listed")
                try expect(directory.files == [LibraryFile(name: "Intro.flac", path: "Intro.flac")], "expected only Candidate Music Files to be listed")
            }
        }
    }

    static func rejectsInvalidMusicLibraryRoot() throws {
        let missingRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try buildApplication(
                libraryRoot: missingRoot,
                host: "127.0.0.1",
                port: 8080
            )
            throw TestFailure.expectationFailed("expected invalid Music Library Root to be rejected")
        } catch TestFailure.expectationFailed {
            throw TestFailure.expectationFailed("expected invalid Music Library Root to be rejected")
        } catch {
            // Any domain error is enough for this first startup-boundary behavior.
        }
    }

    static func serveCommandUsesLocalOnlyDefaults() throws {
        let libraryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        var command = try ServeCommand.parse([
            "--library",
            libraryRoot.path,
        ])

        try expect(command.library == libraryRoot.path, "expected CLI library option to be parsed")
        try expect(command.host == "127.0.0.1", "expected local-only default host")
        try expect(command.port == 8080, "expected default API port")
        try command.validate()
    }
}
