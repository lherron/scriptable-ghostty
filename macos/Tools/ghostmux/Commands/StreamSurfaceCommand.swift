import Foundation

struct StreamSurfaceCommand: GhostmuxCommand {
    static let name = "stream-surface"
    static let aliases = ["stream"]
    static let help = """
    Usage:
      ghostmux stream-surface -t <target> [options]

    Stream raw PTY output from a terminal in real-time.

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      --raw                 Output raw bytes (default: decode as UTF-8 text)
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var raw = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]

            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--raw" {
                raw = true
                i += 1
                continue
            }

            if arg == "-h" || arg == "--help" {
                print(help)
                return
            }

            throw GhostmuxError.message("unexpected argument: \(arg)")
        }

        // Resolve target
        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("stream-surface requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        let terminals = try context.client.listTerminals()
        guard let terminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        // Stream output
        try streamOutput(terminalId: terminal.id, raw: raw, client: context.client)
    }

    private static func streamOutput(terminalId: String, raw: Bool, client: GhostmuxClient) throws {
        // Connect to UDS
        let fd = try connectSocket(client.socketPath)

        // Set up signal handler for clean exit
        signal(SIGINT) { _ in
            exit(0)
        }
        signal(SIGTERM) { _ in
            exit(0)
        }

        // Send stream request
        let request: [String: Any] = [
            "version": "v2",
            "method": "GET",
            "path": "/terminals/\(terminalId)/stream"
        ]
        try sendFrame(fd, request)

        // Read initial response
        guard let initialResponse = try? readFrame(fd) else {
            close(fd)
            throw GhostmuxError.message("failed to read initial response")
        }

        // Check for error
        if let status = initialResponse["status"] as? Int, status != 200 {
            close(fd)
            let message = (initialResponse["body"] as? [String: Any])?["message"] as? String ?? "stream failed"
            throw GhostmuxError.message(message)
        }

        // Read frames continuously
        do {
            while true {
                let frame = try readFrame(fd)

                if let event = frame["event"] as? String, event == "output",
                   let b64 = frame["data"] as? String,
                   let data = Data(base64Encoded: b64) {
                    if raw {
                        FileHandle.standardOutput.write(data)
                    } else {
                        if let text = String(data: data, encoding: .utf8) {
                            writeStdout(text)
                        } else {
                            // Fallback to raw if not valid UTF-8
                            FileHandle.standardOutput.write(data)
                        }
                    }
                }
            }
        } catch {
            FileHandle.standardError.write("stream error: \(error)\n".data(using: .utf8)!)
        }

        close(fd)
    }

    // MARK: - Socket Helpers

    private static func connectSocket(_ socketPath: String) throws -> Int32 {
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
            throw GhostmuxError.message("failed to connect to socket")
        }

        return fd
    }

    private static func sendFrame(_ fd: Int32, _ object: [String: Any]) throws {
        guard let json = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            throw GhostmuxError.message("failed to serialize request")
        }

        var length = UInt32(json.count).bigEndian
        var frame = Data()
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(json)

        var total = 0
        while total < frame.count {
            let written = frame.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: total)
                return write(fd, base, frame.count - total)
            }
            if written <= 0 {
                throw GhostmuxError.message("failed to write to socket")
            }
            total += written
        }
    }

    private static func readFrame(_ fd: Int32) throws -> [String: Any] {
        // Read 4-byte length
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        var offset = 0
        while offset < 4 {
            let result = lengthBytes.withUnsafeMutableBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                return read(fd, base, 4 - offset)
            }
            if result < 0 {
                if errno == EINTR { continue }
                throw GhostmuxError.message("read error: \(errno)")
            }
            if result == 0 {
                throw GhostmuxError.message("connection closed")
            }
            offset += result
        }

        let lengthValue = Data(lengthBytes).withUnsafeBytes { $0.load(as: UInt32.self) }
        let length = Int(UInt32(bigEndian: lengthValue))

        if length <= 0 || length > 10_000_000 {
            throw GhostmuxError.message("invalid frame length: \(length)")
        }

        // Read payload
        var payload = [UInt8](repeating: 0, count: length)
        offset = 0
        while offset < length {
            let result = payload.withUnsafeMutableBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                return read(fd, base, length - offset)
            }
            if result < 0 {
                if errno == EINTR { continue }
                throw GhostmuxError.message("read error: \(errno)")
            }
            if result == 0 {
                throw GhostmuxError.message("connection closed mid-frame")
            }
            offset += result
        }

        let data = Data(payload)
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            throw GhostmuxError.message("invalid JSON response")
        }

        return dict
    }
}
