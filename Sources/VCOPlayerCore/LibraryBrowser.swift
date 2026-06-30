import Foundation
import Hummingbird

public struct LibraryFolder: Codable, Equatable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct LibraryFile: Codable, Equatable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct LibraryDirectory: ResponseCodable, Equatable, Sendable {
    public let path: String
    public let folders: [LibraryFolder]
    public let files: [LibraryFile]

    public init(path: String, folders: [LibraryFolder], files: [LibraryFile]) {
        self.path = path
        self.folders = folders
        self.files = files
    }
}

enum LibraryPathError: Error {
    case invalid
}

private let candidateMusicFileExtensions: Set<String> = ["flac", "wav", "aiff", "aif", "m4a"]

func browseLibraryDirectory(libraryRoot: URL, relativePath: String) throws -> LibraryDirectory {
    try validateLibraryRelativePath(relativePath)

    let resolvedLibraryRoot = libraryRoot.resolvingSymlinksInPath().standardizedFileURL
    let directoryURL = libraryRoot.appendingPathComponent(relativePath, isDirectory: true)
    try validateResolvedLibraryBoundary(resolvedLibraryRoot: resolvedLibraryRoot, candidateURL: directoryURL)

    let entries = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
    )
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

    let folders = try entries.compactMap { entry -> LibraryFolder? in
        guard isResolvedURL(entry, insideOrEqualTo: resolvedLibraryRoot) else {
            return nil
        }
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            return nil
        }
        return LibraryFolder(
            name: entry.lastPathComponent,
            path: joinLibraryPath(relativePath, entry.lastPathComponent)
        )
    }

    let files = try entries.compactMap { entry -> LibraryFile? in
        guard isResolvedURL(entry, insideOrEqualTo: resolvedLibraryRoot) else {
            return nil
        }
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory != true else {
            return nil
        }
        guard candidateMusicFileExtensions.contains(entry.pathExtension.lowercased()) else {
            return nil
        }
        return LibraryFile(
            name: entry.lastPathComponent,
            path: joinLibraryPath(relativePath, entry.lastPathComponent)
        )
    }

    return LibraryDirectory(path: relativePath, folders: folders, files: files)
}

func resolveCandidateMusicFile(libraryRoot: URL, relativePath: String) throws -> String {
    try validateLibraryRelativePath(relativePath)

    let resolvedLibraryRoot = libraryRoot.resolvingSymlinksInPath().standardizedFileURL
    let fileURL = libraryRoot.appendingPathComponent(relativePath, isDirectory: false)
    try validateResolvedLibraryBoundary(resolvedLibraryRoot: resolvedLibraryRoot, candidateURL: fileURL)

    let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory != true else {
        throw LibraryPathError.invalid
    }
    guard candidateMusicFileExtensions.contains(fileURL.pathExtension.lowercased()) else {
        throw LibraryPathError.invalid
    }

    return relativePath
}

func collectCandidateMusicFiles(libraryRoot: URL, relativePath: String) throws -> [String] {
    try validateLibraryRelativePath(relativePath)

    let resolvedLibraryRoot = libraryRoot.resolvingSymlinksInPath().standardizedFileURL
    let directoryURL = libraryRoot.appendingPathComponent(relativePath, isDirectory: true)
    try validateResolvedLibraryBoundary(resolvedLibraryRoot: resolvedLibraryRoot, candidateURL: directoryURL)

    let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else {
        throw LibraryPathError.invalid
    }

    var candidatePaths: [String] = []
    try collectCandidateMusicFiles(
        from: directoryURL,
        relativePath: relativePath,
        resolvedLibraryRoot: resolvedLibraryRoot,
        into: &candidatePaths
    )
    return candidatePaths.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
}

private func collectCandidateMusicFiles(
    from directoryURL: URL,
    relativePath: String,
    resolvedLibraryRoot: URL,
    into candidatePaths: inout [String]
) throws {
    let entries = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
    )

    for entry in entries {
        guard isResolvedURL(entry, insideOrEqualTo: resolvedLibraryRoot) else {
            continue
        }

        let entryPath = joinLibraryPath(relativePath, entry.lastPathComponent)
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try collectCandidateMusicFiles(
                from: entry,
                relativePath: entryPath,
                resolvedLibraryRoot: resolvedLibraryRoot,
                into: &candidatePaths
            )
        } else if candidateMusicFileExtensions.contains(entry.pathExtension.lowercased()) {
            candidatePaths.append(entryPath)
        }
    }
}

private func validateLibraryRelativePath(_ relativePath: String) throws {
    guard !relativePath.hasPrefix("/") else {
        throw LibraryPathError.invalid
    }

    guard !relativePath.split(separator: "/").contains("..") else {
        throw LibraryPathError.invalid
    }
}

private func validateResolvedLibraryBoundary(resolvedLibraryRoot: URL, candidateURL: URL) throws {
    let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL
    guard isPath(resolvedCandidate.path, insideOrEqualTo: resolvedLibraryRoot.path) else {
        throw LibraryPathError.invalid
    }
}

private func isResolvedURL(_ candidateURL: URL, insideOrEqualTo resolvedLibraryRoot: URL) -> Bool {
    let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL
    return isPath(resolvedCandidate.path, insideOrEqualTo: resolvedLibraryRoot.path)
}

private func isPath(_ candidatePath: String, insideOrEqualTo rootPath: String) -> Bool {
    candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
}

private func joinLibraryPath(_ parent: String, _ name: String) -> String {
    guard !parent.isEmpty else {
        return name
    }
    return "\(parent)/\(name)"
}
