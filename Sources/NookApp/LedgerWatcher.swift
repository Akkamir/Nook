import Foundation

@MainActor
final class LedgerWatcher {
    private let ledgerURL: URL
    private var source: DispatchSourceProtocol?
    var onChange: (() -> Void)?

    init(ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".pixelvillage/ledger.json")) {
        self.ledgerURL = ledgerURL
    }

    func start() {
        guard source == nil else { return }

        // Ensure the file exists before watching
        ensureFileExists()

        // Watch the parent directory to catch atomic (rename-based) writes
        let watchURL = ledgerURL.deletingLastPathComponent()
        let fd = open(watchURL.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else {
            print("[LedgerWatcher] Cannot open \(watchURL.path(percentEncoded: false))")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.onChange?()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
        print("[LedgerWatcher] Watching \(watchURL.path(percentEncoded: false))")
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func ensureFileExists() {
        let dir = ledgerURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[LedgerWatcher] Cannot create directory: \(error)")
            return
        }
        if !FileManager.default.fileExists(atPath: ledgerURL.path(percentEncoded: false)) {
            let empty = LedgerState.empty
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601  // must match VillageEngine's decoder
            if let data = try? encoder.encode(empty) {
                try? data.write(to: ledgerURL)
            }
        }
    }
}
