import CoreServices
import Foundation

final class RepositoryFileWatcher: @unchecked Sendable {
    private final class CallbackBox {
        let onChange: @Sendable ([String]) -> Void

        init(onChange: @escaping @Sendable ([String]) -> Void) {
            self.onChange = onChange
        }
    }

    private let queue = DispatchQueue(label: "com.hengyee.GitIgnore.repository-watcher", qos: .utility)
    private var stream: FSEventStreamRef?

    func start(path: String, onChange: @escaping @Sendable ([String]) -> Void) {
        stop()
        let callbackBox = CallbackBox(onChange: onChange)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<CallbackBox>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<CallbackBox>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, pathsPointer, _, _ in
            guard let info else { return }
            let callbackBox = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
            guard count > 0, !paths.isEmpty else { return }
            callbackBox.onChange(paths)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.22,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
