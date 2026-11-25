import Foundation
import CoreServices

/// Calls back on the main queue when something changes under any of `paths`.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init(paths: [String], onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, rawPaths, _, _ in
            guard let info else { return }
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange(paths)
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
