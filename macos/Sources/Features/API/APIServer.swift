import Foundation
import Network
import OSLog

/// Manages the localhost REST API server for Ghostty
final class APIServer {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "APIServer"
    )

    private var listener: NWListener?
    private let port: UInt16
    private let router: APICoreRouter
    private let adapter = APIHTTPAdapter()
    private let socketServer: APISocketServer
    private let queue = DispatchQueue(label: "com.mitchellh.ghostty.api-server", qos: .userInitiated)

    /// Whether the server is currently running
    private(set) var isRunning: Bool = false

    init(port: UInt16, surfaceProvider: @escaping @MainActor () -> [Ghostty.SurfaceView]) {
        self.port = port
        self.router = APICoreRouter(surfaceProvider: surfaceProvider)
        self.socketServer = APISocketServer(surfaceProvider: surfaceProvider)
    }

    /// Start the API server
    func start() throws {
        guard !isRunning else {
            logger.warning("API server already running")
            return
        }

        // Create TCP parameters
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        // Create the listener
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw APIServerError.invalidPort(port)
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw APIServerError.listenerCreationFailed(error)
        }

        // Handle state updates
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isRunning = true
                self.logger.info("API server listening on http://127.0.0.1:\(self.port)")
            case .failed(let error):
                self.isRunning = false
                self.logger.error("API server failed: \(error)")
            case .cancelled:
                self.isRunning = false
                self.logger.info("API server stopped")
            default:
                break
            }
        }

        // Handle new connections
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        // Start listening
        listener?.start(queue: queue)

        do {
            try socketServer.start()
        } catch {
            logger.error("Failed to start UDS server: \(error)")
        }
    }

    /// Stop the API server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        socketServer.stop()
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(connection)
            case .failed(let error):
                self?.logger.debug("Connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveRequest(_ connection: NWConnection) {
        // Receive up to 64KB of data (should be enough for any reasonable API request)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                self.logger.debug("Receive error: \(error)")
                connection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                self.processRequest(data: data, connection: connection)
            } else if isComplete {
                connection.cancel()
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Parse the HTTP request
        guard let request = HTTPRequest.parse(data: data) else {
            sendResponse(.badRequest("Invalid HTTP request"), connection: connection)
            return
        }

        logger.debug("API request: \(request.method) \(request.path)")

        // Route request and get response - dispatch to main actor for thread safety
        Task { @MainActor in
            let apiRequest = self.adapter.toAPIRequest(request)
            let apiResponse = self.router.route(apiRequest)
            let httpResponse = self.adapter.toHTTPResponse(apiResponse)
            self.sendResponse(httpResponse, connection: connection)
        }
    }

    private func sendResponse(_ response: HTTPResponse, connection: NWConnection) {
        let responseData = response.serialize()

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.debug("Send error: \(error)")
            }
            connection.cancel()
        })
    }
}

// MARK: - Errors

enum APIServerError: LocalizedError {
    case invalidPort(UInt16)
    case listenerCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid port number: \(port)"
        case .listenerCreationFailed(let error):
            return "Failed to create listener: \(error.localizedDescription)"
        }
    }
}
