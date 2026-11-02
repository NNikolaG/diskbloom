import CoreServices
import Foundation

/// Asks FSEvents which folders changed since a given event id. macOS keeps this history
/// on every volume, so the app can rescan only those folders instead of the whole disk.
enum ChangeHistory {
    enum Result: Sendable, Equatable {
        /// Folders that changed (each to be rescanned with everything below it).
        case changed(Set<String>)
        /// The history cannot be trusted (wrapped ids, dropped events, a changed root):
        /// rescan everything.
        case unknown
    }

    static var currentEventID: UInt64 { FSEventsGetCurrentEventId() }

    /// Replays events under `roots` since `eventID` and returns once the history is done
    /// (or after `timeout`, as `.unknown`).
    static func changes(under roots: [String], since eventID: UInt64,
                        timeout: Duration = .seconds(20)) async -> Result {
        guard eventID > 0 else { return .unknown }
        let collector = Collector()
        return await withCheckedContinuation { continuation in
            collector.start(roots: roots, since: eventID, continuation: continuation)
            Task {
                try? await Task.sleep(for: timeout)
                collector.finish(.unknown)
            }
        }
    }

    /// Owns the stream and gathers events. FSEvents calls back on `queue`; `finish` may be
    /// called from any thread, so state is guarded by `lock`.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "diskbloom.fsevents")
        private var stream: FSEventStreamRef?
        private var changed: Set<String> = []
        private var untrusted = false
        private var continuation: CheckedContinuation<Result, Never>?

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        func start(roots: [String], since eventID: UInt64, continuation: CheckedContinuation<Result, Never>) {
            locked { self.continuation = continuation }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, count, eventPaths, eventFlags, _ in
                    guard let info else { return }
                    let collector = Unmanaged<Collector>.fromOpaque(info).takeUnretainedValue()
                    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                    let paths = (cfPaths as NSArray) as? [String] ?? []
                    collector.receive(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
                },
                &context, roots as CFArray, eventID, 0.1, flags
            )
            guard let stream else { return finish(.unknown) }
            locked { self.stream = stream }
            FSEventStreamSetDispatchQueue(stream, queue)
            if !FSEventStreamStart(stream) { finish(.unknown) }
        }

        private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
            let historyDone = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
            let distrust = FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped
                                                   | kFSEventStreamEventFlagKernelDropped
                                                   | kFSEventStreamEventFlagUserDropped
                                                   | kFSEventStreamEventFlagRootChanged)
            let result: Result? = locked {
                var done = false
                for (path, flag) in zip(paths, flags) {
                    if flag & historyDone != 0 {
                        done = true
                    } else if flag & distrust != 0 {
                        untrusted = true
                    } else {
                        // Without file-level events, each path is a folder whose contents changed.
                        changed.insert(path)
                    }
                }
                guard done else { return nil }
                return untrusted ? .unknown : .changed(changed)
            }
            if let result { finish(result) }
        }

        func finish(_ result: Result) {
            let (stream, continuation) = locked { () -> (FSEventStreamRef?, CheckedContinuation<Result, Never>?) in
                defer {
                    self.stream = nil
                    self.continuation = nil
                }
                return (self.stream, self.continuation)
            }
            if let stream {
                nonisolated(unsafe) let stream = stream
                // Tear down after the current callback (if any) has returned.
                queue.async {
                    FSEventStreamStop(stream)
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                }
            }
            continuation?.resume(returning: result)
        }
    }
}
