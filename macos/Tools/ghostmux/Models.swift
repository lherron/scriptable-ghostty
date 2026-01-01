import Foundation

struct Terminal {
    let id: String
    let title: String
    let workingDirectory: String?
    let focused: Bool
    let columns: Int?
    let rows: Int?
    let cellWidth: Int?
    let cellHeight: Int?
}

struct CreateTerminalRequest {
    var location: String?
    var workingDirectory: String?
    var command: String?
    var env: [String: String]?
    var parent: String?

    func toBody() -> [String: Any] {
        var body: [String: Any] = [:]
        if let location {
            body["location"] = location
        }
        if let workingDirectory {
            body["working_directory"] = workingDirectory
        }
        if let command {
            body["command"] = command
        }
        if let env {
            body["env"] = env
        }
        if let parent {
            body["parent"] = parent
        }
        return body
    }
}

struct KeyStroke {
    let key: String
    let mods: [String]
    let text: String?
    let unshiftedCodepoint: UInt32
}

extension Terminal {
    func toJsonDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "focused": focused,
        ]
        if let workingDirectory {
            dict["working_directory"] = workingDirectory
        }
        if let columns {
            dict["columns"] = columns
        }
        if let rows {
            dict["rows"] = rows
        }
        if let cellWidth {
            dict["cell_width"] = cellWidth
        }
        if let cellHeight {
            dict["cell_height"] = cellHeight
        }
        return dict
    }
}
