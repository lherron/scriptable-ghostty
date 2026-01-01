import Foundation

struct ListSessionsCommand: GhostmuxCommand {
    static let name = "list-surfaces"
    static let aliases = ["list-sessions", "ls"]
    static let help = """
    Usage:
      ghostmux list-surfaces

    List all terminals.
    """

    static func run(context: CommandContext) throws {
        if context.args.contains("-h") || context.args.contains("--help") {
            print(help)
            return
        }

        let terminals = try context.client.listTerminals()
        if terminals.isEmpty {
            print("(no terminals)")
            return
        }
        for terminal in terminals {
            let shortId = String(terminal.id.prefix(8))
            let size = terminal.columns.flatMap { columns in
                terminal.rows.map { rows in "[\(columns)x\(rows)]" }
            }

            var titlePart = terminal.title
            if let cwd = terminal.workingDirectory {
                titlePart += " (\(cwd))"
            }

            var parts: [String] = [titlePart]
            if let size {
                parts.append(size)
            }
            parts.append(shortId)
            if terminal.focused {
                parts.append("(focused)")
            }

            print(parts.joined(separator: " "))
        }
    }
}
