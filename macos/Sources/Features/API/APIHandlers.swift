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
    func apiInfo() -> HTTPResponse {
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
    func listSurfaces() -> HTTPResponse {
        let surfaces = surfaceProvider()
        let models = surfaces.map { surfaceModel(from: $0) }
        return .json(SurfacesResponse(surfaces: models))
    }

    /// GET /api/v1/surfaces/{uuid} - Get a specific surface
    @MainActor
    func getSurface(uuid: String) -> HTTPResponse {
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
    func getFocusedSurface() -> HTTPResponse {
        let surfaces = surfaceProvider()
        guard let focused = surfaces.first(where: { $0.focused }) else {
            return .notFound("No focused surface")
        }

        return .json(surfaceModel(from: focused))
    }

    // MARK: - Commands

    /// GET /api/v1/surfaces/{uuid}/commands - List available commands for a surface
    @MainActor
    func listCommands(surfaceUUID: String) -> HTTPResponse {
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
    func getScreenContents(surfaceUUID: String) -> HTTPResponse {
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
    func executeAction(surfaceUUID: String, body: Data?) -> HTTPResponse {
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

    // MARK: - Model Conversion

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
}
