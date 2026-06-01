import Foundation

@MainActor
final class ClaudeProjectsWatcher {
    private let fm = FileManager.default
    private let projectsURL: URL
    private let debounceInterval: TimeInterval

    private var rootSource: DispatchSourceProtocol?
    private var projectSources: [String: DispatchSourceProtocol] = [:]
    private var jsonlSources: [String: DispatchSourceProtocol] = [:]
    private var pendingChange: DispatchWorkItem?

    var onChange: (() -> Void)?

    init(
        projectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        debounceInterval: TimeInterval = 0.3
    ) {
        self.projectsURL = projectsURL
        self.debounceInterval = debounceInterval
    }

    func start() {
        guard rootSource == nil else { return }
        do {
            try fm.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        } catch {
            print("[ClaudeProjectsWatcher] Cannot create \(projectsURL.path): \(error)")
            return
        }

        refreshProjectSources()
        rootSource = makeFileSystemSource(for: projectsURL) { [weak self] in
            self?.refreshProjectSources()
            self?.scheduleChange()
        }
        print("[ClaudeProjectsWatcher] Watching \(projectsURL.path)")
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        rootSource?.cancel()
        rootSource = nil
        for source in projectSources.values {
            source.cancel()
        }
        projectSources.removeAll()
        for source in jsonlSources.values {
            source.cancel()
        }
        jsonlSources.removeAll()
    }

    private func refreshProjectSources() {
        let directories = projectDirectories()
        let wantedPaths = Set(directories.map(\.path))

        let stalePaths = projectSources.keys.filter { !wantedPaths.contains($0) }
        for path in stalePaths {
            projectSources[path]?.cancel()
            projectSources.removeValue(forKey: path)
        }

        for directory in directories where projectSources[directory.path] == nil {
            guard let source = makeFileSystemSource(for: directory, onEvent: { [weak self] in
                self?.refreshProjectSources()
                self?.scheduleChange()
            }) else { continue }
            projectSources[directory.path] = source
        }

        refreshJSONLSources(in: directories)
    }

    private func projectDirectories() -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    private func refreshJSONLSources(in directories: [URL]) {
        let files = directories.flatMap(jsonlFiles(in:))
        let wantedPaths = Set(files.map(\.path))

        let stalePaths = jsonlSources.keys.filter { !wantedPaths.contains($0) }
        for path in stalePaths {
            jsonlSources[path]?.cancel()
            jsonlSources.removeValue(forKey: path)
        }

        for file in files where jsonlSources[file.path] == nil {
            guard let source = makeFileSystemSource(for: file, onEvent: { [weak self] in
                self?.refreshProjectSources()
                self?.scheduleChange()
            }) else { continue }
            jsonlSources[file.path] = source
        }
    }

    private func jsonlFiles(in directory: URL) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return entries.filter { url in
            url.pathExtension == "jsonl"
                && ((try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true)
        }
    }

    private func makeFileSystemSource(for url: URL, onEvent: @escaping () -> Void) -> DispatchSourceProtocol? {
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else {
            print("[ClaudeProjectsWatcher] Cannot open \(url.path(percentEncoded: false))")
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        return source
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        pendingChange = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
