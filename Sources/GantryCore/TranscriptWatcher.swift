import CoreServices
import Foundation

/// Watches Claude Code's projects folder with FSEvents and reports the
/// transcript files that changed, so auto-sync reacts without polling.
public final class TranscriptWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([URL]) -> Void

    /// `latency` lets FSEvents coalesce the burst of writes Claude Code makes
    /// while it streams a reply. Returns nil when the stream cannot start,
    /// for example when the folder does not exist yet.
    public init?(
        directory: URL,
        latency: TimeInterval = 1,
        queue: DispatchQueue = .main,
        onChange: @escaping ([URL]) -> Void
    ) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let urls = list.prefix(count)
                .filter { $0.hasSuffix(".jsonl") }
                .map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty { watcher.onChange(urls) }
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
