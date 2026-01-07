import Foundation

// MARK: - Request Models

/// Request body for executing an action
struct ActionRequest: Codable {
    let action: String
}

/// Request body for creating a terminal (v2)
struct CreateTerminalRequest: Codable {
    let location: String?
    let command: String?
    let workingDirectory: String?
    let env: [String: String]?
    let parent: String?
}

/// Request body for sending text (v2)
struct InputTextRequest: Codable {
    let text: String
    let enter: Bool?
}

/// Request body for sending output data (v2)
struct OutputRequest: Codable {
    let data: String
}

/// Request body for setting terminal title (v2)
struct SetTitleRequest: Codable {
    let title: String
}

/// Request body for setting the programmable status bar (v2)
struct StatusBarRequest: Codable {
    let left: String?
    let center: String?
    let right: String?
    let visible: Bool?
    let toggle: Bool?
    let scope: String?
}

/// Request body for key events (v2)
struct KeyEventRequest: Codable {
    let key: String
    let mods: [String]?
    let action: String?
    let text: String?
    let unshiftedCodepoint: UInt32?
}

/// Request body for mouse button events (v2)
struct MouseButtonRequest: Codable {
    let button: String
    let action: String?
    let mods: [String]?
}

/// Request body for mouse position events (v2)
struct MousePositionRequest: Codable {
    let x: Double
    let y: Double
    let mods: [String]?
}

/// Request body for mouse scroll events (v2)
struct MouseScrollRequest: Codable {
    let x: Double?
    let y: Double?
    let precision: Bool?
    let momentum: String?
}

// MARK: - Response Models

/// Response containing a list of surfaces
struct SurfacesResponse: Codable {
    let surfaces: [SurfaceModel]
}

/// Model representing a terminal surface
struct SurfaceModel: Codable {
    let id: String
    let title: String
    let workingDirectory: String?
    let focused: Bool
    let columns: Int?
    let rows: Int?
    let cellWidth: Int?
    let cellHeight: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, focused, columns, rows
        case workingDirectory = "working_directory"
        case cellWidth = "cell_width"
        case cellHeight = "cell_height"
    }
}

/// Response containing a list of commands
struct CommandsResponse: Codable {
    let commands: [CommandModel]
}

/// Model representing a command
struct CommandModel: Codable {
    let actionKey: String
    let action: String
    let title: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case action, title, description
        case actionKey = "action_key"
    }
}

/// Response for action execution
struct ActionResponse: Codable {
    let success: Bool
    let action: String
    let error: String?

    init(success: Bool, action: String, error: String? = nil) {
        self.success = success
        self.action = action
        self.error = error
    }
}

/// Response containing a list of terminals (v2)
struct TerminalsResponseV2: Codable {
    let terminals: [TerminalModelV2]
}

/// Model representing a terminal (v2)
struct TerminalModelV2: Codable {
    let id: String
    let title: String
    let workingDirectory: String?
    let kind: String
    let focused: Bool
    let columns: Int?
    let rows: Int?
    let cellWidth: Int?
    let cellHeight: Int?
}

/// Response for terminal detail lookup (v2)
struct TerminalDetailsResponse: Codable {
    let type: String
    let value: String?
}

/// Response for quick terminal (v2)
struct QuickTerminalResponse: Codable {
    let terminals: [TerminalModelV2]
}

/// Generic success response (v2)
struct SuccessResponse: Codable {
    let success: Bool
}

/// Generic error response
struct ErrorResponse: Codable {
    let error: String
    let message: String
}

/// API info response
struct APIInfoResponse: Codable {
    let version: String
    let endpoints: [String]
}

/// Response containing screen contents
struct ScreenContentsResponse: Codable {
    let id: String
    let contents: String
}
