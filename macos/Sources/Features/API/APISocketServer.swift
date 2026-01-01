import Foundation
import OSLog

/// Manages the Unix domain socket control server for Ghostty
final class APISocketServer {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "APISocketServer"
    )

    private let router: APICoreRouter
    private let acceptQueue = DispatchQueue(label: "com.mitchellh.ghostty.api-uds.accept", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(label: "com.mitchellh.ghostty.api-uds.connection", qos: .userInitiated, attributes: .concurrent)
    private let socketURL: URL

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    /// Whether the server is currently running
    private(set) var isRunning: Bool = false

    init(
        surfaceProvider: @escaping @MainActor () -> [Ghostty.SurfaceView],
        socketURL: URL? = nil
    ) {
        self.router = APICoreRouter(surfaceProvider: surfaceProvider)
        self.socketURL = socketURL ?? APISocketServer.defaultSocketURL()
    }

    /// Start the UDS server
    func start() throws {
        guard !isRunning else {
            logger.warning("UDS server already running")
            return
        }

        try prepareSocketPath()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw APISocketServerError.socketCreationFailed(errno)
        }

        listenFD = fd

        var flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = self.socketURL.path
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else {
            close(fd)
            listenFD = -1
            throw APISocketServerError.socketPathTooLong(path)
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLength) { raw in
                _ = path.withCString { cstr in
                    strncpy(UnsafeMutablePointer(mutating: raw), cstr, maxLength)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if bindResult != 0 {
            let code = errno
            close(fd)
            listenFD = -1
            throw APISocketServerError.bindFailed(code)
        }

        if listen(fd, SOMAXCONN) != 0 {
            let code = errno
            close(fd)
            listenFD = -1
            throw APISocketServerError.listenFailed(code)
        }

        setSocketPermissions()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenFD >= 0 {
                close(self.listenFD)
                self.listenFD = -1
            }
        }
        source.resume()
        acceptSource = source

        isRunning = true
        logger.info("UDS server listening at \(self.socketURL.path)")
    }

    /// Stop the UDS server
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        isRunning = false
        cleanupSocketPath()
    }

    // MARK: - Accept/Connection Handling

    private func acceptConnections() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                logger.debug("UDS accept failed: \(errno)")
                return
            }

            connectionQueue.async { [weak self] in
                self?.handleConnection(clientFD)
            }
        }
    }

    private func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        guard let lengthData = readExact(fd, count: 4) else {
            return
        }

        let lengthValue = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
        let length = Int(UInt32(bigEndian: lengthValue))
        if length <= 0 {
            return
        }

        guard let payload = readExact(fd, count: length) else {
            return
        }

        processUDSRequest(data: payload, fd: fd)
    }

    private func processUDSRequest(data: Data, fd: Int32) {
        let envelope: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = object as? [String: Any] else {
                sendUDSResponse(.badRequest("Invalid request envelope"), id: nil, fd: fd)
                return
            }
            envelope = dict
        } catch {
            sendUDSResponse(.badRequest("Invalid JSON request"), id: nil, fd: fd)
            return
        }

        let id = envelope["id"] as? String
        guard let version = envelope["version"] as? String,
              let method = envelope["method"] as? String,
              let path = envelope["path"] as? String else {
            sendUDSResponse(.badRequest("Missing required fields"), id: id, fd: fd)
            return
        }

        var query: [String: String] = [:]
        if let queryDict = envelope["query"] as? [String: Any] {
            for (key, value) in queryDict {
                if let stringValue = value as? String {
                    query[key] = stringValue
                } else {
                    query[key] = String(describing: value)
                }
            }
        } else if let queryDict = envelope["query"] as? [String: String] {
            query = queryDict
        }

        var body: Data?
        if let bodyObject = envelope["body"] {
            body = try? JSONSerialization.data(withJSONObject: bodyObject, options: [])
        }

        let request = APIRequest(
            id: id,
            version: version,
            method: method,
            path: path,
            query: query,
            body: body
        )

        let response = routeOnMainActor(request)
        sendUDSResponse(response, id: id, fd: fd)
    }

    private func sendUDSResponse(_ response: APIResponse, id: String?, fd: Int32) {
        var envelope: [String: Any] = [
            "status": response.statusCode
        ]

        if let id {
            envelope["id"] = id
        }

        if !response.headers.isEmpty {
            envelope["headers"] = response.headers
        }

        if let body = response.body,
           let json = try? JSONSerialization.jsonObject(with: body, options: []) {
            envelope["body"] = json
        }

        let payload = (try? JSONSerialization.data(withJSONObject: envelope, options: [])) ?? Data()
        sendFrame(payload, fd: fd)
    }

    private func sendFrame(_ payload: Data, fd: Int32) {
        var length = UInt32(payload.count).bigEndian
        var frame = Data()
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)

        _ = writeAll(fd, data: frame)
    }

    private func routeOnMainActor(_ request: APIRequest) -> APIResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var result: APIResponse = .internalError("Main actor routing failed")

        Task { @MainActor in
            result = self.router.route(request)
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Socket Path Helpers

    private func prepareSocketPath() throws {
        let directory = self.socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if FileManager.default.fileExists(atPath: self.socketURL.path) {
            try FileManager.default.removeItem(at: self.socketURL)
        }
    }

    private func cleanupSocketPath() {
        if FileManager.default.fileExists(atPath: self.socketURL.path) {
            try? FileManager.default.removeItem(at: self.socketURL)
        }
    }

    private func setSocketPermissions() {
        _ = chmod(self.socketURL.path, 0o600)
    }

    private static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Ghostty", isDirectory: true)
            .appendingPathComponent("api.sock")
    }

    // MARK: - IO Helpers

    private func readExact(_ fd: Int32, count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0

        while offset < count {
            let result = buffer.withUnsafeMutableBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                return read(fd, base, count - offset)
            }

            if result <= 0 {
                return nil
            }

            offset += result
        }

        return Data(buffer)
    }

    private func writeAll(_ fd: Int32, data: Data) -> Bool {
        var total = 0
        let count = data.count

        while total < count {
            let written = data.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: total)
                return write(fd, base, count - total)
            }

            if written <= 0 {
                return false
            }

            total += written
        }

        return true
    }
}

enum APISocketServerError: LocalizedError {
    case socketCreationFailed(Int32)
    case socketPathTooLong(String)
    case bindFailed(Int32)
    case listenFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let code):
            return "Failed to create socket: \(errnoDescription(code))"
        case .socketPathTooLong(let path):
            return "Socket path too long: \(path)"
        case .bindFailed(let code):
            return "Failed to bind socket: \(errnoDescription(code))"
        case .listenFailed(let code):
            return "Failed to listen on socket: \(errnoDescription(code))"
        }
    }

    private func errnoDescription(_ code: Int32) -> String {
        if let cstr = strerror(code) {
            return String(cString: cstr)
        }
        return "errno \(code)"
    }
}
