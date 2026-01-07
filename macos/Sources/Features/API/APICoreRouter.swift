import Foundation

/// Routes incoming API requests to appropriate handlers (transport-agnostic)
final class APICoreRouter {
    private let handlers: APIHandlers

    init(surfaceProvider: @escaping @MainActor () -> [Ghostty.SurfaceView]) {
        self.handlers = APIHandlers(surfaceProvider: surfaceProvider)
    }

    /// Route a request and return the appropriate response
    @MainActor
    func route(_ request: APIRequest) -> APIResponse {
        // Validate API version
        if request.version.isEmpty {
            return .notFound("Invalid API path. Expected /api/v1/... or /api/v2/...")
        }

        // Parse path into components, removing empty strings from leading/trailing slashes
        let pathComponents = request.path
            .split(separator: "/")
            .map(String.init)

        // Handle root path
        if pathComponents.isEmpty {
            switch request.version {
            case "v1":
                return handlers.apiInfo()
            case "v2":
                return handlers.apiInfoV2()
            default:
                return .notFound("Invalid API version. Expected v1 or v2")
            }
        }

        switch request.version {
        case "v1":
            return routeAPIRequestV1(method: request.method, path: pathComponents, body: request.body)
        case "v2":
            return routeAPIRequestV2(
                method: request.method,
                path: pathComponents,
                query: request.query,
                body: request.body
            )
        default:
            return .notFound("Invalid API version. Expected v1 or v2")
        }
    }

    @MainActor
    private func routeAPIRequestV1(method: String, path: [String], body: Data?) -> APIResponse {
        switch path.count {
        case 0:
            if method == "GET" {
                return handlers.apiInfo()
            }
            return .methodNotAllowed(["GET"])

        case 1:
            if path[0] == "surfaces" {
                if method == "GET" {
                    return handlers.listSurfaces()
                }
                return .methodNotAllowed(["GET"])
            }
            return .notFound("Endpoint not found")

        case 2:
            if path[0] == "surfaces" {
                if path[1] == "focused" {
                    if method == "GET" {
                        return handlers.getFocusedSurface()
                    }
                    return .methodNotAllowed(["GET"])
                }
                if method == "GET" {
                    return handlers.getSurface(uuid: path[1])
                }
                return .methodNotAllowed(["GET"])
            }
            return .notFound("Endpoint not found")

        case 3:
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

    @MainActor
    private func routeAPIRequestV2(
        method: String,
        path: [String],
        query: [String: String],
        body: Data?
    ) -> APIResponse {
        switch path.count {
        case 0:
            if method == "GET" {
                return handlers.apiInfoV2()
            }
            return .methodNotAllowed(["GET"])

        case 1:
            switch path[0] {
            case "terminals":
                if method == "GET" {
                    return handlers.listTerminalsV2()
                }
                if method == "POST" {
                    return handlers.createTerminalV2(body: body)
                }
                return .methodNotAllowed(["GET", "POST"])
            case "quick-terminal":
                if method == "POST" {
                    return handlers.openQuickTerminalV2()
                }
                return .methodNotAllowed(["POST"])
            case "commands":
                if method == "GET" {
                    return handlers.listCommandsV2(terminalUUID: query["terminal"])
                }
                return .methodNotAllowed(["GET"])
            default:
                return .notFound("Endpoint not found")
            }

        case 2:
            if path[0] == "terminals" {
                if path[1] == "focused" {
                    if method == "GET" {
                        return handlers.getFocusedTerminalV2()
                    }
                    return .methodNotAllowed(["GET"])
                }

                let uuid = path[1]
                switch method {
                case "GET":
                    return handlers.getTerminalV2(uuid: uuid)
                case "DELETE":
                    let confirm = handlers.parseQueryBool(query["confirm"])
                    return handlers.closeTerminalV2(uuid: uuid, confirm: confirm)
                default:
                    return .methodNotAllowed(["GET", "DELETE"])
                }
            }
            return .notFound("Endpoint not found")

        case 3:
            if path[0] == "terminals" {
                let uuid = path[1]
                switch path[2] {
                case "focus":
                    if method == "POST" {
                        return handlers.focusTerminalV2(uuid: uuid)
                    }
                    return .methodNotAllowed(["POST"])
                case "input":
                    if method == "POST" {
                        return handlers.inputTerminalV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "output":
                    if method == "POST" {
                        return handlers.outputTerminalV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "title":
                    if method == "POST" {
                        return handlers.setTerminalTitleV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "statusbar":
                    if method == "POST" {
                        return handlers.setStatusBarV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "action":
                    if method == "POST" {
                        return handlers.actionTerminalV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "key":
                    if method == "POST" {
                        return handlers.keyTerminalV2(uuid: uuid, body: body)
                    }
                    return .methodNotAllowed(["POST"])
                case "screen":
                    if method == "GET" {
                        return handlers.getScreenContentsV2(uuid: uuid)
                    }
                    return .methodNotAllowed(["GET"])
                default:
                    return .notFound("Endpoint not found")
                }
            }
            return .notFound("Endpoint not found")

        case 4:
            if path[0] == "terminals" {
                let uuid = path[1]
                switch path[2] {
                case "details":
                    if method == "GET" {
                        return handlers.getTerminalDetailsV2(uuid: uuid, detail: path[3])
                    }
                    return .methodNotAllowed(["GET"])
                case "mouse":
                    if method == "POST" {
                        switch path[3] {
                        case "button":
                            return handlers.mouseButtonV2(uuid: uuid, body: body)
                        case "position":
                            return handlers.mousePositionV2(uuid: uuid, body: body)
                        case "scroll":
                            return handlers.mouseScrollV2(uuid: uuid, body: body)
                        default:
                            return .notFound("Endpoint not found")
                        }
                    }
                    return .methodNotAllowed(["POST"])
                default:
                    return .notFound("Endpoint not found")
                }
            }
            return .notFound("Endpoint not found")

        default:
            return .notFound("Endpoint not found: \(method) /api/v2/\(path.joined(separator: "/"))")
        }
    }
}
