import Foundation

/// Routes incoming HTTP requests to appropriate handlers
final class APIRouter {
    private let handlers: APIHandlers

    init(surfaceProvider: @escaping @MainActor () -> [Ghostty.SurfaceView]) {
        self.handlers = APIHandlers(surfaceProvider: surfaceProvider)
    }

    /// Route a request and return the appropriate response
    @MainActor
    func route(_ request: HTTPRequest) -> HTTPResponse {
        // Parse path into components, removing empty strings from leading/trailing slashes
        let pathComponents = request.path
            .split(separator: "/")
            .map(String.init)

        // Handle root path
        if pathComponents.isEmpty {
            return handlers.apiInfo()
        }

        // Validate API version prefix
        guard pathComponents.count >= 2,
              pathComponents[0] == "api",
              pathComponents[1] == "v1" else {
            return .notFound("Invalid API path. Expected /api/v1/...")
        }

        // Get the API path without the prefix
        let apiPath = Array(pathComponents.dropFirst(2))

        // Route based on method and path
        return routeAPIRequest(method: request.method, path: apiPath, body: request.body)
    }

    @MainActor
    private func routeAPIRequest(method: String, path: [String], body: Data?) -> HTTPResponse {
        // Handle based on path length and components
        switch path.count {
        case 0:
            // GET /api/v1
            if method == "GET" {
                return handlers.apiInfo()
            }
            return .methodNotAllowed(["GET"])

        case 1:
            // /api/v1/surfaces
            if path[0] == "surfaces" {
                if method == "GET" {
                    return handlers.listSurfaces()
                }
                return .methodNotAllowed(["GET"])
            }
            return .notFound("Endpoint not found")

        case 2:
            // /api/v1/surfaces/{uuid} or /api/v1/surfaces/focused
            if path[0] == "surfaces" {
                if path[1] == "focused" {
                    if method == "GET" {
                        return handlers.getFocusedSurface()
                    }
                    return .methodNotAllowed(["GET"])
                }
                // Assume it's a UUID
                if method == "GET" {
                    return handlers.getSurface(uuid: path[1])
                }
                return .methodNotAllowed(["GET"])
            }
            return .notFound("Endpoint not found")

        case 3:
            // /api/v1/surfaces/{uuid}/commands, /api/v1/surfaces/{uuid}/actions, or /api/v1/surfaces/{uuid}/screen
            if path[0] == "surfaces" {
                let uuid = path[1]
                if path[2] == "commands" {
                    if method == "GET" {
                        return handlers.listCommands(surfaceUUID: uuid)
                    }
                    return .methodNotAllowed(["GET"])
                }
                if path[2] == "actions" {
                    if method == "POST" {
                        return handlers.executeAction(surfaceUUID: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                }
                if path[2] == "screen" {
                    if method == "GET" {
                        return handlers.getScreenContents(surfaceUUID: uuid)
                    }
                    return .methodNotAllowed(["GET"])
                }
            }
            return .notFound("Endpoint not found")

        default:
            return .notFound("Endpoint not found: \(method) /api/v1/\(path.joined(separator: "/"))")
        }
    }
}
