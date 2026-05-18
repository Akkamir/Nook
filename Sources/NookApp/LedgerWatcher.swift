import Foundation

final class LedgerWatcher {
    private let ledgerURL: URL
    private var source: DispatchSourceProtocol?
    var onChange: (() -> Void)?

    init(ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".pixelvillage/ledger.json")) {
        self.ledgerURL = ledgerURL
    }

    func start() {
        // Ensure the file exists before watching
        ensureFileExists()

        let fd = open(ledgerURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[LedgerWatcher] Cannot open \(ledgerURL.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.onChange?()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
        print("[LedgerWatcher] Watching \(ledgerURL.path)")
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func ensureFileExists() {
        let dir = ledgerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: ledgerURL.path) {
            let empty = LedgerState.empty
            if let data = try? JSONEncoder().encode(empty) {
                try? data.write(to: ledgerURL)
            }
        }
    }
}
