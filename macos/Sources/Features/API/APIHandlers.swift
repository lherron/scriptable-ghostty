import AppKit
import Foundation

/// Implements the API endpoint handlers
final class APIHandlers {
    /// Closure that returns all available surfaces
    private let surfaceProvider: @MainActor () -> [Ghostty.SurfaceView]

    init(surfaceProvider: @escaping @MainActor () -> [Ghostty.SurfaceView]) {
        self.surfaceProvider = surfaceProvider
    }

    // MARK: - API Info

    /// GET /api/v1 - Return API information
    @MainActor
    func apiInfo() -> APIResponse {
        let info = APIInfoResponse(
            version: "1",
            endpoints: [
                "GET /api/v1/surfaces",
                "GET /api/v1/surfaces/focused",
                "GET /api/v1/surfaces/{uuid}",
                "GET /api/v1/surfaces/{uuid}/commands",
                "GET /api/v1/surfaces/{uuid}/screen",
                "POST /api/v1/surfaces/{uuid}/actions"
            ]
        )
        return .json(info)
    }

    // MARK: - Surfaces

    /// GET /api/v1/surfaces - List all surfaces
    @MainActor
    func listSurfaces() -> APIResponse {
        let surfaces = surfaceProvider()
        let models = surfaces.map { surfaceModel(from: $0) }
        return .json(SurfacesResponse(surfaces: models))
    }

    /// GET /api/v1/surfaces/{uuid} - Get a specific surface
    @MainActor
    func getSurface(uuid: String) -> APIResponse {
        guard let surfaceUUID = UUID(uuidString: uuid) else {
            return .badRequest("Invalid UUID format")
        }

        let surfaces = surfaceProvider()
        guard let surface = surfaces.first(where: { $0.id == surfaceUUID }) else {
            return .notFound("Surface not found: \(uuid)")
        }

        return .json(surfaceModel(from: surface))
    }

    /// GET /api/v1/surfaces/focused - Get the focused surface
    @MainActor
    func getFocusedSurface() -> APIResponse {
        let surfaces = surfaceProvider()
        guard let focused = surfaces.first(where: { $0.focused }) else {
            return .notFound("No focused surface")
        }

        return .json(surfaceModel(from: focused))
    }

    // MARK: - Commands

    /// GET /api/v1/surfaces/{uuid}/commands - List available commands for a surface
    @MainActor
    func listCommands(surfaceUUID: String) -> APIResponse {
        guard let uuid = UUID(uuidString: surfaceUUID) else {
            return .badRequest("Invalid UUID format")
        }

        let surfaces = surfaceProvider()
        guard surfaces.first(where: { $0.id == uuid }) != nil else {
            return .notFound("Surface not found: \(surfaceUUID)")
        }

        // Commands come from the global config, not individual surfaces
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return .internalError("No app delegate")
        }

        let commands = appDelegate.ghostty.config.commandPaletteEntries
        let models = commands.map { commandModel(from: $0) }
        return .json(CommandsResponse(commands: models))
    }

    // MARK: - Screen Contents

    /// GET /api/v1/surfaces/{uuid}/screen - Get screen contents for a surface
    @MainActor
    func getScreenContents(surfaceUUID: String) -> APIResponse {
        guard let uuid = UUID(uuidString: surfaceUUID) else {
            return .badRequest("Invalid UUID format")
        }

        let surfaces = surfaceProvider()
        guard let surface = surfaces.first(where: { $0.id == uuid }) else {
            return .notFound("Surface not found: \(surfaceUUID)")
        }

        let contents = surface.cachedScreenContents.get()
        return .json(ScreenContentsResponse(id: surfaceUUID, contents: contents))
    }

    // MARK: - Actions

    /// POST /api/v1/surfaces/{uuid}/actions - Execute an action on a surface
    @MainActor
    func executeAction(surfaceUUID: String, body: Data?) -> APIResponse {
        guard let uuid = UUID(uuidString: surfaceUUID) else {
            return .badRequest("Invalid UUID format")
        }

        guard let body = body else {
            return .badRequest("Request body is required")
        }

        let request: ActionRequest
        do {
            request = try JSONDecoder().decode(ActionRequest.self, from: body)
        } catch {
            return .badRequest("Invalid request body: \(error.localizedDescription)")
        }

        let surfaces = surfaceProvider()
        guard let surface = surfaces.first(where: { $0.id == uuid }) else {
            return .notFound("Surface not found: \(surfaceUUID)")
        }

        guard let surfaceModel = surface.surfaceModel else {
            return .internalError("Surface has no model")
        }

        let success = surfaceModel.perform(action: request.action)
        if success {
            return .json(ActionResponse(success: true, action: request.action))
        } else {
            return .json(ActionResponse(
                success: false,
                action: request.action,
                error: "Action failed or not recognized"
            ))
        }
    }

    // MARK: - v2 API Info

    /// GET /api/v2 - Return API information
    @MainActor
    func apiInfoV2() -> APIResponse {
        let info = APIInfoResponse(
            version: "2",
            endpoints: [
                "GET /api/v2/terminals",
                "GET /api/v2/terminals/focused",
                "GET /api/v2/terminals/{id}",
                "POST /api/v2/terminals",
                "DELETE /api/v2/terminals/{id}",
                "POST /api/v2/terminals/{id}/focus",
                "POST /api/v2/terminals/{id}/input",
                "POST /api/v2/terminals/{id}/title",
                "POST /api/v2/terminals/{id}/statusbar",
                "POST /api/v2/terminals/{id}/action",
                "POST /api/v2/terminals/{id}/key",
                "POST /api/v2/terminals/{id}/mouse/button",
                "POST /api/v2/terminals/{id}/mouse/position",
                "POST /api/v2/terminals/{id}/mouse/scroll",
                "GET /api/v2/terminals/{id}/screen",
                "GET /api/v2/terminals/{id}/details/{type}",
                "POST /api/v2/quick-terminal",
                "GET /api/v2/commands"
            ]
        )
        return .json(info)
    }

    // MARK: - v2 Terminal Management

    /// GET /api/v2/terminals - List all terminals
    @MainActor
    func listTerminalsV2() -> APIResponse {
        let surfaces = surfaceProvider()
        let models = surfaces.map { terminalModelV2(from: $0) }
        return .json(TerminalsResponseV2(terminals: models))
    }

    /// GET /api/v2/terminals/focused - Get the focused terminal
    @MainActor
    func getFocusedTerminalV2() -> APIResponse {
        let surfaces = surfaceProvider()
        guard let focused = surfaces.first(where: { $0.focused }) else {
            return v2Error("no_focused_terminal", "No terminal is currently focused", statusCode: 404)
        }
        return .json(terminalModelV2(from: focused))
    }

    /// GET /api/v2/terminals/{id} - Get a specific terminal
    @MainActor
    func getTerminalV2(uuid: String) -> APIResponse {
        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            return .json(terminalModelV2(from: surface))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals - Create a new terminal
    @MainActor
    func createTerminalV2(body: Data?) -> APIResponse {
        let request: CreateTerminalRequest
        switch decodeV2Request(CreateTerminalRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        let locationValue = request.location ?? "window"
        guard let location = NewTerminalLocation(rawValue: locationValue) else {
            return v2Error("invalid_location", "Invalid terminal location: \(locationValue)", statusCode: 400)
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return v2Error("action_failed", "App unavailable", statusCode: 500)
        }

        var config = Ghostty.SurfaceConfiguration()
        if let command = request.command, !command.isEmpty {
            config.initialInput = "\(command); exit\n"
        }
        if let workingDirectory = request.workingDirectory {
            config.workingDirectory = workingDirectory
        }
        if let env = request.env {
            config.environmentVariables = env
        }

        let parentSurfaceResult = resolveParentSurface(parentID: request.parent)
        let parentSurface: Ghostty.SurfaceView?
        switch parentSurfaceResult {
        case .success(let surface):
            parentSurface = surface
        case .failure(let response):
            return response
        }

        if location.splitDirection != nil && parentSurface == nil {
            return v2Error("no_focused_terminal", "No terminal is currently focused", statusCode: 404)
        }

        let ghostty = appDelegate.ghostty

        switch location {
        case .window:
            let controller = TerminalController.newWindow(
                ghostty,
                withBaseConfig: config,
                withParent: parentSurface?.window
            )
            if let view = controller.surfaceTree.root?.leftmostLeaf() {
                return .json(terminalModelV2(from: view))
            }

        case .tab:
            let controller = TerminalController.newTab(
                ghostty,
                from: parentSurface?.window,
                withBaseConfig: config
            )
            if let view = controller?.surfaceTree.root?.leftmostLeaf() {
                return .json(terminalModelV2(from: view))
            }

        case .splitLeft, .splitRight, .splitUp, .splitDown:
            guard let parentSurface,
                  let controller = parentSurface.window?.windowController as? BaseTerminalController,
                  let direction = location.splitDirection else {
                return v2Error("terminal_not_found", "Parent terminal not found", statusCode: 404)
            }

            if let view = controller.newSplit(
                at: parentSurface,
                direction: direction,
                baseConfig: config
            ) {
                return .json(terminalModelV2(from: view))
            }
        }

        return v2Error("action_failed", "Failed to create terminal", statusCode: 500)
    }

    /// DELETE /api/v2/terminals/{id} - Close a terminal
    @MainActor
    func closeTerminalV2(uuid: String, confirm: Bool) -> APIResponse {
        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let controller = surface.window?.windowController as? BaseTerminalController else {
                return v2Error("action_failed", "Terminal controller unavailable", statusCode: 500)
            }
            controller.closeSurface(surface, withConfirmation: confirm)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/focus - Focus a terminal
    @MainActor
    func focusTerminalV2(uuid: String) -> APIResponse {
        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let controller = surface.window?.windowController as? BaseTerminalController else {
                return v2Error("action_failed", "Terminal controller unavailable", statusCode: 500)
            }
            controller.focusSurface(surface)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    // MARK: - v2 Input & Actions

    /// POST /api/v2/terminals/{id}/input - Send text input
    @MainActor
    func inputTerminalV2(uuid: String, body: Data?) -> APIResponse {
        let request: InputTextRequest
        switch decodeV2Request(InputTextRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            surfaceModel.sendText(request.text)
            if request.enter == true {
                let event = Ghostty.Input.KeyEvent(
                    key: .enter,
                    action: .press,
                    mods: Ghostty.Input.Mods()
                )
                surfaceModel.sendKeyEvent(event)
            }
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/title - Set terminal title
    @MainActor
    func setTerminalTitleV2(uuid: String, body: Data?) -> APIResponse {
        let request: SetTitleRequest
        switch decodeV2Request(SetTitleRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            surface.setTitle(request.title)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/statusbar - Set programmable status bar
    @MainActor
    func setStatusBarV2(uuid: String, body: Data?) -> APIResponse {
        let request: StatusBarRequest
        switch decodeV2Request(StatusBarRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        if request.left == nil && request.center == nil && request.right == nil &&
            request.visible == nil && request.toggle == nil {
            return v2Error(
                "missing_field",
                "At least one of left, center, right, visible, or toggle is required",
                statusCode: 400
            )
        }

        let scope = request.scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scope, scope != "surface" && scope != "window" {
            return v2Error("invalid_action", "Invalid scope: \(scope)", statusCode: 400)
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let controller = surface.window?.windowController as? BaseTerminalController else {
                return v2Error("action_failed", "Terminal controller unavailable", statusCode: 500)
            }

            let useWindowScope = scope == "window"
            var state = useWindowScope
                ? (controller.windowStatusBarState ?? .hidden)
                : (controller.statusBarStateForSurface(surface) ?? .hidden)

            if let left = request.left { state.left = left }
            if let center = request.center { state.center = center }
            if let right = request.right { state.right = right }

            if request.toggle == true {
                state.visible.toggle()
            } else if let visible = request.visible {
                state.visible = visible
            }

            if useWindowScope {
                controller.setWindowStatusBar(state: state)
            } else {
                controller.setStatusBar(for: surface, state: state)
            }

            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/action - Execute a keybind action
    @MainActor
    func actionTerminalV2(uuid: String, body: Data?) -> APIResponse {
        let request: ActionRequest
        switch decodeV2Request(ActionRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        if request.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v2Error("invalid_action", "Action must not be empty", statusCode: 400)
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            let success = surfaceModel.perform(action: request.action)
            if success {
                return .json(ActionResponse(success: true, action: request.action))
            }
            return v2Error("action_failed", "Action failed or not recognized", statusCode: 500)
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/key - Send key events
    @MainActor
    func keyTerminalV2(uuid: String, body: Data?) -> APIResponse {
        let request: KeyEventRequest
        switch decodeV2Request(KeyEventRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        guard let key = ghosttyKey(from: request.key) else {
            return v2Error("invalid_action", "Invalid key: \(request.key)", statusCode: 400)
        }

        let mods: Ghostty.Input.Mods
        switch ghosttyMods(from: request.mods ?? []) {
        case .success(let value): mods = value
        case .failure(let response): return response
        }

        let actionValue = request.action?.lowercased()
        let action: Ghostty.Input.Action
        switch actionValue {
        case nil, "press":
            action = .press
        case "release":
            action = .release
        case "repeat":
            action = .repeat
        default:
            return v2Error("invalid_action", "Invalid key action: \(request.action ?? "")", statusCode: 400)
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            let event = Ghostty.Input.KeyEvent(
                key: key,
                action: action,
                text: request.text,
                mods: mods,
                unshiftedCodepoint: request.unshiftedCodepoint ?? 0
            )
            surfaceModel.sendKeyEvent(event)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    // MARK: - v2 Mouse

    /// POST /api/v2/terminals/{id}/mouse/button - Send mouse button event
    @MainActor
    func mouseButtonV2(uuid: String, body: Data?) -> APIResponse {
        let request: MouseButtonRequest
        switch decodeV2Request(MouseButtonRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        let buttonValue = request.button.lowercased()
        let button: Ghostty.Input.MouseButton
        switch buttonValue {
        case "left": button = .left
        case "right": button = .right
        case "middle": button = .middle
        default:
            return v2Error("invalid_action", "Invalid mouse button: \(request.button)", statusCode: 400)
        }

        let actionValue = request.action?.lowercased()
        let action: Ghostty.Input.MouseState
        switch actionValue {
        case nil, "press":
            action = .press
        case "release":
            action = .release
        default:
            return v2Error("invalid_action", "Invalid mouse action: \(request.action ?? "")", statusCode: 400)
        }

        let mods: Ghostty.Input.Mods
        switch ghosttyMods(from: request.mods ?? []) {
        case .success(let value): mods = value
        case .failure(let response): return response
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            let event = Ghostty.Input.MouseButtonEvent(action: action, button: button, mods: mods)
            surfaceModel.sendMouseButton(event)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/mouse/position - Send mouse position event
    @MainActor
    func mousePositionV2(uuid: String, body: Data?) -> APIResponse {
        let request: MousePositionRequest
        switch decodeV2Request(MousePositionRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        let mods: Ghostty.Input.Mods
        switch ghosttyMods(from: request.mods ?? []) {
        case .success(let value): mods = value
        case .failure(let response): return response
        }

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            let event = Ghostty.Input.MousePosEvent(x: request.x, y: request.y, mods: mods)
            surfaceModel.sendMousePos(event)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/terminals/{id}/mouse/scroll - Send mouse scroll event
    @MainActor
    func mouseScrollV2(uuid: String, body: Data?) -> APIResponse {
        let request: MouseScrollRequest
        switch decodeV2Request(MouseScrollRequest.self, body: body) {
        case .success(let value): request = value
        case .failure(let response): return response
        }

        let momentumValue = request.momentum?.lowercased()
        let momentum: Ghostty.Input.Momentum
        switch momentumValue {
        case nil, "none":
            momentum = .none
        case "began":
            momentum = .began
        case "changed":
            momentum = .changed
        case "ended":
            momentum = .ended
        case "cancelled", "canceled":
            momentum = .cancelled
        case "stationary":
            momentum = .stationary
        case "may_begin", "maybegin":
            momentum = .mayBegin
        default:
            return v2Error("invalid_action", "Invalid momentum value: \(request.momentum ?? "")", statusCode: 400)
        }

        let precision = request.precision ?? false
        let x = request.x ?? 0
        let y = request.y ?? 0

        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            guard let surfaceModel = surface.surfaceModel else {
                return v2Error("action_failed", "Terminal model unavailable", statusCode: 500)
            }
            let event = Ghostty.Input.MouseScrollEvent(
                x: x,
                y: y,
                mods: .init(precision: precision, momentum: momentum)
            )
            surfaceModel.sendMouseScroll(event)
            return .json(SuccessResponse(success: true))
        case .failure(let response):
            return response
        }
    }

    // MARK: - v2 Details & Commands

    /// GET /api/v2/terminals/{id}/screen - Get screen contents
    @MainActor
    func getScreenContentsV2(uuid: String) -> APIResponse {
        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            let contents = surface.cachedScreenContents.get()
            return .json(ScreenContentsResponse(id: uuid, contents: contents))
        case .failure(let response):
            return response
        }
    }

    /// GET /api/v2/terminals/{id}/details/{type} - Get specific terminal details
    @MainActor
    func getTerminalDetailsV2(uuid: String, detail: String) -> APIResponse {
        switch surfaceViewV2(uuid: uuid) {
        case .success(let surface):
            switch detail {
            case "title":
                return .json(TerminalDetailsResponse(type: detail, value: surface.title))
            case "working_directory":
                return .json(TerminalDetailsResponse(type: detail, value: surface.pwd))
            case "contents":
                return .json(TerminalDetailsResponse(type: detail, value: surface.cachedScreenContents.get()))
            case "selection":
                return .json(TerminalDetailsResponse(type: detail, value: surface.accessibilitySelectedText()))
            case "visible":
                return .json(TerminalDetailsResponse(type: detail, value: surface.cachedVisibleContents.get()))
            default:
                return v2Error("invalid_action", "Invalid detail type: \(detail)", statusCode: 400)
            }
        case .failure(let response):
            return response
        }
    }

    /// POST /api/v2/quick-terminal - Open the quick terminal
    @MainActor
    func openQuickTerminalV2() -> APIResponse {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return v2Error("action_failed", "App unavailable", statusCode: 500)
        }

        let controller = delegate.quickController
        controller.animateIn()

        let terminals = controller.surfaceTree.root?.leaves().map {
            terminalModelV2(from: $0)
        } ?? []

        return .json(QuickTerminalResponse(terminals: terminals))
    }

    /// GET /api/v2/commands - List available commands
    @MainActor
    func listCommandsV2(terminalUUID: String?) -> APIResponse {
        if let terminalUUID {
            guard let uuid = UUID(uuidString: terminalUUID) else {
                return v2Error("invalid_uuid", "Invalid UUID format", statusCode: 400)
            }
            let surfaces = surfaceProvider()
            guard surfaces.first(where: { $0.id == uuid }) != nil else {
                return v2Error("terminal_not_found", "Terminal not found: \(terminalUUID)", statusCode: 404)
            }
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return v2Error("action_failed", "App unavailable", statusCode: 500)
        }

        let commands = appDelegate.ghostty.config.commandPaletteEntries
        let models = commands.map { commandModel(from: $0) }
        return .json(CommandsResponse(commands: models))
    }

    // MARK: - Utilities

    func parseQueryBool(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return value == "true" || value == "1" || value == "yes" || value == "on"
    }

    // MARK: - Model Conversion

    private enum V2Result<T> {
        case success(T)
        case failure(APIResponse)
    }

    @MainActor
    private func surfaceModel(from surface: Ghostty.SurfaceView) -> SurfaceModel {
        return SurfaceModel(
            id: surface.id.uuidString,
            title: surface.title,
            workingDirectory: surface.pwd,
            focused: surface.focused,
            columns: surface.surfaceSize.map { Int($0.columns) },
            rows: surface.surfaceSize.map { Int($0.rows) },
            cellWidth: surface.surfaceSize.map { Int($0.cell_width_px) },
            cellHeight: surface.surfaceSize.map { Int($0.cell_height_px) }
        )
    }

    private func commandModel(from command: Ghostty.Command) -> CommandModel {
        return CommandModel(
            actionKey: command.actionKey,
            action: command.action,
            title: command.title,
            description: command.description
        )
    }

    @MainActor
    private func terminalModelV2(from surface: Ghostty.SurfaceView) -> TerminalModelV2 {
        let kind: String
        if surface.window?.windowController is QuickTerminalController {
            kind = "quick"
        } else {
            kind = "normal"
        }

        return TerminalModelV2(
            id: surface.id.uuidString,
            title: surface.title,
            workingDirectory: surface.pwd,
            kind: kind,
            focused: surface.focused,
            columns: surface.surfaceSize.map { Int($0.columns) },
            rows: surface.surfaceSize.map { Int($0.rows) },
            cellWidth: surface.surfaceSize.map { Int($0.cell_width_px) },
            cellHeight: surface.surfaceSize.map { Int($0.cell_height_px) }
        )
    }

    @MainActor
    private func surfaceViewV2(uuid: String) -> V2Result<Ghostty.SurfaceView> {
        guard let surfaceUUID = UUID(uuidString: uuid) else {
            return .failure(v2Error("invalid_uuid", "Invalid UUID format", statusCode: 400))
        }

        let surfaces = surfaceProvider()
        guard let surface = surfaces.first(where: { $0.id == surfaceUUID }) else {
            return .failure(v2Error("terminal_not_found", "Terminal not found: \(uuid)", statusCode: 404))
        }

        return .success(surface)
    }

    @MainActor
    private func resolveParentSurface(parentID: String?) -> V2Result<Ghostty.SurfaceView?> {
        guard let parentID else {
            let focused = surfaceProvider().first(where: { $0.focused })
            return .success(focused)
        }

        guard let uuid = UUID(uuidString: parentID) else {
            return .failure(v2Error("invalid_uuid", "Invalid UUID format", statusCode: 400))
        }

        let surfaces = surfaceProvider()
        guard let surface = surfaces.first(where: { $0.id == uuid }) else {
            return .failure(v2Error("terminal_not_found", "Terminal not found: \(parentID)", statusCode: 404))
        }

        return .success(surface)
    }

    private func decodeV2Request<T: Decodable>(_ type: T.Type, body: Data?) -> V2Result<T> {
        guard let body else {
            return .failure(v2Error("missing_field", "Request body is required", statusCode: 400))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let request = try decoder.decode(T.self, from: body)
            return .success(request)
        } catch DecodingError.keyNotFound(let key, _) {
            return .failure(v2Error("missing_field", "Missing field: \(key.stringValue)", statusCode: 400))
        } catch DecodingError.valueNotFound(_, let context) {
            return .failure(v2Error("missing_field", context.debugDescription, statusCode: 400))
        } catch DecodingError.typeMismatch(_, let context) {
            return .failure(v2Error("invalid_json", context.debugDescription, statusCode: 400))
        } catch DecodingError.dataCorrupted(let context) {
            return .failure(v2Error("invalid_json", context.debugDescription, statusCode: 400))
        } catch {
            return .failure(v2Error("invalid_json", "Invalid JSON body", statusCode: 400))
        }
    }

    private func v2Error(_ code: String, _ message: String, statusCode: Int) -> APIResponse {
        APIResponse.json(ErrorResponse(error: code, message: message), statusCode: statusCode)
    }

    private func ghosttyMods(from mods: [String]) -> V2Result<Ghostty.Input.Mods> {
        var result = Ghostty.Input.Mods()

        for mod in mods {
            let value = mod.lowercased()
            switch value {
            case "shift":
                result.insert(.shift)
            case "control", "ctrl":
                result.insert(.ctrl)
            case "option", "alt":
                result.insert(.alt)
            case "command", "cmd", "super", "meta":
                result.insert(.super)
            default:
                return .failure(v2Error("invalid_action", "Invalid modifier: \(mod)", statusCode: 400))
            }
        }

        return .success(result)
    }

    private func ghosttyKey(from key: String) -> Ghostty.Input.Key? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Ghostty.Input.Key(rawValue: trimmed) {
            return direct
        }

        let lower = trimmed.lowercased()
        if let directLower = Ghostty.Input.Key(rawValue: lower) {
            return directLower
        }

        if lower.count == 1 {
            if let scalar = lower.unicodeScalars.first {
                if CharacterSet.letters.contains(scalar) {
                    return Ghostty.Input.Key(rawValue: lower)
                }
                if CharacterSet.decimalDigits.contains(scalar) {
                    return Ghostty.Input.Key(rawValue: "digit\(lower)")
                }
            }
        }

        let normalized = lower.replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "enter", "return":
            return .enter
        case "escape", "esc":
            return .escape
        case "tab":
            return .tab
        case "space":
            return .space
        case "backspace":
            return .backspace
        case "delete":
            return .delete
        case "up", "arrow_up", "arrowup":
            return .arrowUp
        case "down", "arrow_down", "arrowdown":
            return .arrowDown
        case "left", "arrow_left", "arrowleft":
            return .arrowLeft
        case "right", "arrow_right", "arrowright":
            return .arrowRight
        case "home":
            return .home
        case "end":
            return .end
        case "page_up", "pageup":
            return .pageUp
        case "page_down", "pagedown":
            return .pageDown
        default:
            break
        }

        if normalized.hasPrefix("f"), let number = Int(normalized.dropFirst()) {
            switch number {
            case 1: return .f1
            case 2: return .f2
            case 3: return .f3
            case 4: return .f4
            case 5: return .f5
            case 6: return .f6
            case 7: return .f7
            case 8: return .f8
            case 9: return .f9
            case 10: return .f10
            case 11: return .f11
            case 12: return .f12
            case 13: return .f13
            case 14: return .f14
            case 15: return .f15
            case 16: return .f16
            case 17: return .f17
            case 18: return .f18
            case 19: return .f19
            case 20: return .f20
            case 21: return .f21
            case 22: return .f22
            case 23: return .f23
            case 24: return .f24
            default: return nil
            }
        }

        return nil
    }

    
}
