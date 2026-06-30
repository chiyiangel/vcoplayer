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

@main
struct BackendTestRunner {
    static func main() async {
        do {
            try await statusReturnsIdlePlayerStatusForValidMusicLibraryRoot()
            print("PASS statusReturnsIdlePlayerStatusForValidMusicLibraryRoot")
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
