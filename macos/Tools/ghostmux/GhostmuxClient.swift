import Foundation
import Darwin

final class GhostmuxClient {
    private let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
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
        let fd = try connectSocket()
        defer { close(fd) }

        var length = UInt32(payload.count).bigEndian
        var frame = Data()
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)

        if !writeAll(fd, data: frame) {
            throw GhostmuxError.message("failed to write request")
        }

        guard let header = readExact(fd, count: 4) else {
            throw GhostmuxError.message("short response header")
        }

        let responseLengthValue = header.withUnsafeBytes { $0.load(as: UInt32.self) }
        let responseLength = Int(UInt32(bigEndian: responseLengthValue))
        guard responseLength > 0 else {
            throw GhostmuxError.message("invalid response length")
        }

        guard let response = readExact(fd, count: responseLength) else {
            throw GhostmuxError.message("short response body")
        }

        return response
    }

    private func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw GhostmuxError.message("failed to create socket")
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < maxLength else {
            close(fd)
            throw GhostmuxError.message("socket path too long")
        }

        let nsPath = socketPath as NSString
        strncpy(&addr.sun_path.0, nsPath.fileSystemRepresentation, maxLength)

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result != 0 {
            close(fd)
            throw GhostmuxError.message("cannot connect to Ghostty UDS at \(socketPath)")
        }

        return fd
    }

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
        while total < data.count {
            let written = data.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: total)
                return write(fd, base, data.count - total)
            }
            if written <= 0 {
                return false
            }
            total += written
        }
        return true
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

    var description: String {
        switch self {
        case .message(let message):
            return message
        case .apiError(let status, let message):
            if let message {
                return message
            }
            return "API error (HTTP \(status))"
        }
    }
}
