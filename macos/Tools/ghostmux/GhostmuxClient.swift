import Foundation
import AppKit
import Darwin

final class GhostmuxClient {
    private static let scriptableGhosttyBundleId = "com.lherron.scriptableghostty"
    private static let connectRetryAttempts = 20
    private static let connectRetryDelayMicros: useconds_t = 100_000
    private static let sendRetryAttempts = 10
    private static let sendRetryDelayMicros: useconds_t = 100_000

    private let _socketPath: String
    private var didEnsureScriptableGhostty = false

    /// The path to the UDS socket
    var socketPath: String { _socketPath }

    init(socketPath: String) {
        self._socketPath = socketPath
    }

    func listTerminals() throws -> [Terminal] {
        let response = try request(version: "v2", method: "GET", path: "/terminals")
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        guard let body = response.body,
              let terminals = body["terminals"] as? [[String: Any]] else {
            return []
        }
        return terminals.compactMap(parseTerminal)
    }

    func createTerminal(request: CreateTerminalRequest) throws -> Terminal {
        let response = try self.request(
            version: "v2",
            method: "POST",
            path: "/terminals",
            body: request.toBody()
        )
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        guard let body = response.body, let terminal = parseTerminal(body) else {
            throw GhostmuxError.message("invalid create terminal response")
        }
        return terminal
    }

    func deleteTerminal(terminalId: String, confirm: Bool) throws {
        let query = confirm ? ["confirm": "true"] : [:]
        let response = try request(
            version: "v2",
            method: "DELETE",
            path: "/terminals/\(terminalId)",
            query: query
        )
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("kill-surface failed")
        }
    }

    func isAvailable() -> Bool {
        do {
            let response = try request(version: "v2", method: "GET", path: "/terminals")
            return response.status == 200
        } catch {
            return false
        }
    }

    func sendKey(terminalId: String, stroke: KeyStroke) throws {
        var body: [String: Any] = [
            "key": stroke.key,
            "unshifted_codepoint": stroke.unshiftedCodepoint,
        ]
        if let text = stroke.text {
            body["text"] = text
        }
        if !stroke.mods.isEmpty {
            body["mods"] = stroke.mods
        }
        let response = try request(version: "v2", method: "POST", path: "/terminals/\(terminalId)/key", body: body)
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("send-keys failed")
        }
    }

    func sendText(terminalId: String, text: String) throws {
        let body: [String: Any] = ["text": text]
        let response = try request(version: "v2", method: "POST", path: "/terminals/\(terminalId)/input", body: body)
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("input failed")
        }
    }

    func sendOutput(terminalId: String, data: String) throws {
        let body: [String: Any] = ["data": data]
        let response = try request(version: "v2", method: "POST", path: "/terminals/\(terminalId)/output", body: body)
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("output failed")
        }
    }

    func setTitle(terminalId: String, title: String) throws {
        let body: [String: Any] = ["title": title]
        let response = try request(version: "v2", method: "POST", path: "/terminals/\(terminalId)/title", body: body)
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("set-title failed")
        }
    }

    func setStatusBar(
        terminalId: String,
        left: String? = nil,
        center: String? = nil,
        right: String? = nil,
        visible: Bool? = nil,
        toggle: Bool? = nil,
        scope: String? = nil,
        fg: String? = nil,
        bg: String? = nil
    ) throws {
        var body: [String: Any] = [:]
        if let left { body["left"] = left }
        if let center { body["center"] = center }
        if let right { body["right"] = right }
        if let visible { body["visible"] = visible }
        if let toggle { body["toggle"] = toggle }
        if let scope { body["scope"] = scope }
        if let fg { body["fg"] = fg }
        if let bg { body["bg"] = bg }
        if body.isEmpty {
            throw GhostmuxError.message("statusbar update requires at least one field")
        }

        let response = try request(
            version: "v2",
            method: "POST",
            path: "/terminals/\(terminalId)/statusbar",
            body: body
        )
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        if let success = response.body?["success"] as? Bool, !success {
            throw GhostmuxError.message("statusbar update failed")
        }
    }

    func getScreenContents(terminalId: String) throws -> String {
        let response = try request(version: "v2", method: "GET", path: "/terminals/\(terminalId)/screen")
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        return response.body?["contents"] as? String ?? ""
    }

    func getVisibleContents(terminalId: String) throws -> String {
        let response = try request(version: "v2", method: "GET", path: "/terminals/\(terminalId)/details/visible")
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        return response.body?["value"] as? String ?? ""
    }

    func getSelectionContents(terminalId: String) throws -> String? {
        let response = try request(version: "v2", method: "GET", path: "/terminals/\(terminalId)/details/selection")
        guard response.status == 200 else {
            throw GhostmuxError.apiError(response.status, response.bodyError)
        }
        return response.body?["value"] as? String
    }

    private func request(
        version: String,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) throws -> UDSResponse {
        var envelope: [String: Any] = [
            "version": version,
            "method": method,
            "path": path,
        ]
        if !query.isEmpty {
            envelope["query"] = query
        }
        if let body {
            envelope["body"] = body
        }

        let payload = try JSONSerialization.data(withJSONObject: envelope, options: [])
        let responseData = try sendUDS(payload: payload)
        return try UDSResponse.decode(responseData)
    }

    private func sendUDS(payload: Data) throws -> Data {
        var lastError: GhostmuxError?
        for attempt in 0..<Self.sendRetryAttempts {
            do {
                return try sendUDSOnce(payload: payload)
            } catch let error as GhostmuxError {
                lastError = error
                if shouldRetry(error), attempt < Self.sendRetryAttempts - 1 {
                    usleep(Self.sendRetryDelayMicros)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? GhostmuxError.message("failed to send request")
    }

    private func sendUDSOnce(payload: Data) throws -> Data {
        let fd = try connectSocket()
        defer { close(fd) }

        var length = UInt32(payload.count).bigEndian
        var frame = Data()
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)

        try writeAll(fd, data: frame)

        let header = try readExact(fd, count: 4, context: "response header")

        let responseLengthValue = header.withUnsafeBytes { $0.load(as: UInt32.self) }
        let responseLength = Int(UInt32(bigEndian: responseLengthValue))
        guard responseLength > 0 else {
            throw GhostmuxError.message("invalid response length")
        }

        let response = try readExact(fd, count: responseLength, context: "response body")
        return response
    }

    private func connectSocket() throws -> Int32 {
        try ensureScriptableGhosttyRunning()

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard _socketPath.utf8.count < maxLength else {
            throw GhostmuxError.message("socket path too long")
        }

        let nsPath = _socketPath as NSString
        strncpy(&addr.sun_path.0, nsPath.fileSystemRepresentation, maxLength)

        var lastErrno: Int32 = 0
        for attempt in 0..<Self.connectRetryAttempts {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            if fd < 0 {
                throw GhostmuxError.message("failed to create socket")
            }

            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            let result = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            if result == 0 {
                return fd
            }

            lastErrno = errno
            close(fd)

            if (lastErrno == ENOENT || lastErrno == ECONNREFUSED),
               attempt < Self.connectRetryAttempts - 1 {
                usleep(Self.connectRetryDelayMicros)
                continue
            }
            break
        }

        throw GhostmuxError.message("cannot connect to Ghostty UDS at \(_socketPath)")
    }

    private func readExact(_ fd: Int32, count: Int, context: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0

        while offset < count {
            let result = buffer.withUnsafeMutableBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                return read(fd, base, count - offset)
            }
            if result == 0 {
                throw GhostmuxError.transportRead("short \(context)", 0)
            }
            if result < 0 {
                if errno == EINTR {
                    continue
                }
                throw GhostmuxError.transportRead("short \(context)", errno)
            }
            offset += result
        }

        return Data(buffer)
    }

    private func writeAll(_ fd: Int32, data: Data) throws {
        var total = 0
        while total < data.count {
            let written = data.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: total)
                return write(fd, base, data.count - total)
            }
            if written < 0 {
                if errno == EINTR {
                    continue
                }
                throw GhostmuxError.transportWrite(errno)
            }
            if written == 0 {
                throw GhostmuxError.transportWrite(0)
            }
            total += written
        }
    }

    private func parseTerminal(_ dict: [String: Any]) -> Terminal? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else {
            return nil
        }

        return Terminal(
            id: id,
            title: title,
            workingDirectory: dict["working_directory"] as? String,
            focused: dict["focused"] as? Bool ?? false,
            columns: dict["columns"] as? Int,
            rows: dict["rows"] as? Int,
            cellWidth: dict["cell_width"] as? Int,
            cellHeight: dict["cell_height"] as? Int
        )
    }

    private func ensureScriptableGhosttyRunning() throws {
        if didEnsureScriptableGhostty {
            return
        }
        didEnsureScriptableGhostty = true
        if isScriptableGhosttyRunning() {
            return
        }
        try launchScriptableGhostty()
    }

    private func isScriptableGhosttyRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.scriptableGhosttyBundleId
        ).isEmpty
    }

    private func launchScriptableGhostty() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", "-b", Self.scriptableGhosttyBundleId]
        do {
            try task.run()
        } catch {
            throw GhostmuxError.message("failed to launch ScriptableGhostty")
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw GhostmuxError.message("failed to launch ScriptableGhostty")
        }
    }

    private func shouldRetry(_ error: GhostmuxError) -> Bool {
        switch error {
        case .transportWrite(let code):
            return code == EPIPE || code == ECONNRESET || code == ENOTCONN || code == 0
        case .transportRead(_, let code):
            return code == EPIPE || code == ECONNRESET || code == ENOTCONN || code == 0
        default:
            return false
        }
    }
}

struct UDSResponse {
    let status: Int
    let body: [String: Any]?

    var bodyError: String? {
        if let body, let message = body["message"] as? String {
            return message
        }
        if let body, let error = body["error"] as? String {
            return error
        }
        return nil
    }

    static func decode(_ data: Data) throws -> UDSResponse {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw GhostmuxError.message("invalid response")
        }
        let status = dict["status"] as? Int ?? 500
        let body = dict["body"] as? [String: Any]
        return UDSResponse(status: status, body: body)
    }
}

enum GhostmuxError: Error, CustomStringConvertible {
    case message(String)
    case apiError(Int, String?)
    case transportWrite(Int32)
    case transportRead(String, Int32)

    var description: String {
        switch self {
        case .message(let message):
            return message
        case .apiError(let status, let message):
            if let message {
                return message
            }
            return "API error (HTTP \(status))"
        case .transportWrite:
            return "failed to write request"
        case .transportRead(let message, _):
            return message
        }
    }
}
