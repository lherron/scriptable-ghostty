import Foundation

// MARK: - Request Models

/// Request body for executing an action
struct ActionRequest: Codable {
    let action: String
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
