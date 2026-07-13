import Foundation

/// Watches a single file for on-disk changes using a kqueue-backed dispatch
/// source. Text editors commonly save *atomically* — write a temp file, then
/// rename it over the original — which retires the inode our descriptor points
/// at. So on a rename/delete we tear down and re-arm on the freshly landed
/// inode; plain in-place writes (`.write`/`.extend`) keep the same inode and
/// need no re-arm.
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "solutions.ddj.marklens.filewatcher")
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        guard arm() else { return nil }
    }

    deinit { source?.cancel() }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func arm() -> Bool {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: queue
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            // The original inode was replaced (atomic save) — by now `url.path`
            // resolves to the new file, so read first, then re-arm for the next
            // edit. Plain writes reuse the inode and skip the re-arm.
            let replaced = src.data.contains(.rename)
                || src.data.contains(.delete)
                || src.data.contains(.revoke)

            let notify = self.onChange
            Task { @MainActor in notify() }

            if replaced {
                self.source?.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    _ = self?.arm()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
        return true
    }
}
