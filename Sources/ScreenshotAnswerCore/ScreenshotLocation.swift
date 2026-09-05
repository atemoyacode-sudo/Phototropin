import Foundation

public enum ScreenshotLocation {
    public static func current() -> URL {
        if let configured = configuredLocation(),
           FileManager.default.fileExists(atPath: configured.path) {
            return configured
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private static func configuredLocation() -> URL? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.screencapture", "location"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard var path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            path = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: path, isDirectory: true)
        } catch {
            return nil
        }
    }
}

public enum ScreenshotMonitoringScope {
    public static func directories(standard: URL, custom: URL?) -> [URL] {
        var result: [URL] = []
        var seenPaths = Set<String>()
        for directory in [standard, custom].compactMap({ $0 }) {
            let normalized = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard seenPaths.insert(normalized.path).inserted else { continue }
            result.append(directory)
        }
        return result
    }

    public static func candidateImages(
        in directories: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return directories.flatMap { directory in
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls.filter(ScreenshotFileClassifier.isLikelyScreenshot)
        }
    }
}

public struct TemporaryCaptureStore {
    public let directoryURL: URL

    public init(
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        directoryName: String = "Phototropin-Captures"
    ) {
        directoryURL = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    public func removeAbandonedCaptures(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }
}

public enum ScreenshotFileClassifier {
    public static let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "tif", "tiff"])

    public static func isLikelyScreenshot(_ url: URL) -> Bool {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let knownPrefixes = [
            "screenshot",
            "screen shot",
            "スクリーンショット",
            "capture d’écran",
            "captura de pantalla",
            "bildschirmfoto",
        ]
        return knownPrefixes.contains { name.hasPrefix($0) }
    }
}
