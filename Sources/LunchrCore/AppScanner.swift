import Foundation

public enum AppScanner {
    public static var defaultRoots: [String] {
        [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            NSHomeDirectory() + "/Applications",
        ]
    }

    /// Apps that live outside the scanned folders.
    private static let extras = ["/System/Library/CoreServices/Finder.app"]

    public static func scan(roots: [String] = defaultRoots, includeExtras: Bool = true) -> [AppEntry] {
        var found: [String] = []
        for root in roots { collect(root, depth: 0, into: &found) }
        if includeExtras { found += extras.filter { FileManager.default.fileExists(atPath: $0) } }

        var seen: Set<String> = []
        return found
            .filter { seen.insert(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path).inserted }
            .compactMap(entry)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func collect(_ folder: String, depth: Int, into found: inout [String]) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
        for item in items where !item.hasPrefix(".") {
            let path = folder + "/" + item
            // fileExists follows symlinks: /Applications/Safari.app is one.
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue
            else { continue }
            if item.hasSuffix(".app") {
                found.append(path)
            } else if depth < 2 {
                collect(path, depth: depth + 1, into: &found)
            }
        }
    }

    static func entry(_ path: String) -> AppEntry? {
        // Read the file directly: Bundle caches Info.plist for the life of the process.
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any] ?? [:]
        if (info["LSBackgroundOnly"] as? NSNumber)?.boolValue == true { return nil }

        let name = stripSuffix(FileManager.default.displayName(atPath: path))
        guard !name.isEmpty else { return nil }
        return AppEntry(path: path, name: name, alternateNames: [
            stripSuffix((path as NSString).lastPathComponent),
            info["CFBundleDisplayName"] as? String ?? "",
            info["CFBundleName"] as? String ?? "",
        ])
    }

    private static func stripSuffix(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
