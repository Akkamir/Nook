import Foundation
import Darwin

@MainActor
final class ClaudeHookServer {
    var onEvent: ((ClaudeHookEvent) -> Void)?

    private let pixelVillageDirectory: URL
    private var token = UUID().uuidString
    private(set) var port: Int = 0
    private var worker: ClaudeHookServerWorker?

    init(
        pixelVillageDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage")
    ) {
        self.pixelVillageDirectory = pixelVillageDirectory
    }

    func start() throws {
        guard worker == nil else { return }

        token = UUID().uuidString
        let listener = try Self.makeListeningSocket()
        port = listener.port

        do {
            try writeConfig()
        } catch {
            Darwin.close(listener.fd)
            port = 0
            throw error
        }

        let worker = ClaudeHookServerWorker(socketFD: listener.fd, token: token) { [weak self] event in
            Task { @MainActor in
                self?.onEvent?(event)
            }
        }
        self.worker = worker
        worker.start()
    }

    func stop() {
        worker?.stop()
        worker = nil
        port = 0
    }
}

private extension ClaudeHookServer {
    static func makeListeningSocket() throws -> (fd: Int32, port: Int) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw currentPOSIXError() }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw currentPOSIXError()
        }

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw currentPOSIXError()
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw currentPOSIXError()
        }

        return (fd, Int(UInt16(bigEndian: bound.sin_port)))
    }

    func writeConfig() throws {
        try FileManager.default.createDirectory(at: pixelVillageDirectory, withIntermediateDirectories: true)
        let config = ClaudeHookServerConfig(port: port, token: token)
        let data = try JSONEncoder().encode(config)
        try data.write(to: pixelVillageDirectory.appendingPathComponent("hook-server.json"), options: .atomic)
    }

    static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private final class ClaudeHookServerWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nook.claude-hook-server")
    private let token: String
    private let onEvent: @Sendable (ClaudeHookEvent) -> Void
    private let socketFD: Int32
    private let lock = NSLock()
    private var isStopped = false

    init(socketFD: Int32, token: String, onEvent: @escaping @Sendable (ClaudeHookEvent) -> Void) {
        self.socketFD = socketFD
        self.token = token
        self.onEvent = onEvent
    }

    func start() {
        let fd = socketFD
        queue.async { [self] in
            acceptLoop(socketFD: fd)
        }
    }

    func stop() {
        lock.lock()
        let shouldClose = !isStopped
        isStopped = true
        lock.unlock()

        guard shouldClose else { return }
        Darwin.shutdown(socketFD, SHUT_RDWR)
        Darwin.close(socketFD)
    }

    private func acceptLoop(socketFD: Int32) {
        while true {
            let client = Darwin.accept(socketFD, nil, nil)
            guard client >= 0 else { break }
            handle(client: client)
            Darwin.close(client)
        }
    }

    private func handle(client: Int32) {
        let request: HTTPRequest
        switch readRequest(from: client) {
        case .request(let parsed):
            request = parsed
        case .badRequest:
            writeResponse(client, status: 400)
            return
        case .closed:
            return
        }

        guard request.method == "POST", request.path == "/claude-hook" else {
            writeResponse(client, status: 404)
            return
        }

        guard request.headers["authorization"] == "Bearer \(token)" else {
            writeResponse(client, status: 401)
            return
        }

        guard let event = try? JSONDecoder().decode(ClaudeHookEvent.self, from: request.body) else {
            writeResponse(client, status: 400)
            return
        }

        onEvent(event)
        writeResponse(client, status: 204)
    }
}

private extension ClaudeHookServerWorker {
    enum ReadResult {
        case request(HTTPRequest)
        case badRequest
        case closed
    }

    struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    func readRequest(from client: Int32) -> ReadResult {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Range<Data.Index>?
        var partialRequest: (method: String, path: String, headers: [String: String])?
        var expectedLength: Int?

        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { return .closed }
            data.append(buffer, count: count)

            if headerEnd == nil,
               let range = data.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = range
                guard let parsed = parseHeaders(data: data[..<range.lowerBound]) else {
                    return .badRequest
                }
                partialRequest = parsed

                guard parsed.method == "POST", parsed.path == "/claude-hook" else {
                    return .request(HTTPRequest(
                        method: parsed.method,
                        path: parsed.path,
                        headers: parsed.headers,
                        body: Data()
                    ))
                }

                guard let parsedLength = contentLength(from: parsed.headers) else {
                    return .badRequest
                }
                expectedLength = parsedLength
            }

            if let headerEnd,
               let partialRequest,
               let expectedLength {
                let bodyStart = headerEnd.upperBound
                if data.count - bodyStart >= expectedLength {
                    let bodyEnd = bodyStart + expectedLength
                    guard bodyEnd <= data.endIndex else { return .badRequest }
                    return .request(HTTPRequest(
                        method: partialRequest.method,
                        path: partialRequest.path,
                        headers: partialRequest.headers,
                        body: data[bodyStart..<bodyEnd]
                    ))
                }
            }

            if data.count > 1_048_576 {
                return .badRequest
            }
        }
    }

    func parseHeaders(data: Data.SubSequence) -> (method: String, path: String, headers: [String: String])? {
        guard let headerText = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        return (
            method: requestParts[0],
            path: requestParts[1],
            headers: headers
        )
    }

    func contentLength(from headers: [String: String]) -> Int? {
        guard let rawValue = headers["content-length"],
              let length = Int(rawValue),
              length >= 0 else { return nil }
        return length
    }

    func writeResponse(_ client: Int32, status: Int) {
        let reason = [
            204: "No Content",
            400: "Bad Request",
            401: "Unauthorized",
            404: "Not Found"
        ][status] ?? "OK"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = response.withCString { Darwin.write(client, $0, strlen($0)) }
    }
}
