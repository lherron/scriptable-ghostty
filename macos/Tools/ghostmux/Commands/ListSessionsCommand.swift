import Foundation

struct ListSessionsCommand: GhostmuxCommand {
    static let name = "list-surfaces"
    static let aliases = ["list-sessions", "ls"]

    static func run(context: CommandContext) throws {
        if context.args.contains("-h") || context.args.contains("--help") {
            printUsage()
            return
        }

        let terminals = try context.client.listTerminals()
        if terminals.isEmpty {
            print("(no terminals)")
            return
        }
        for terminal in terminals {
            let shortId = String(terminal.id.prefix(8))
            let size: String
            if let columns = terminal.columns, let rows = terminal.rows {
                size = "[\(columns)x\(rows)]"
            } else {
                size = ""
            }
            let focused = terminal.focused ? " (focused)" : ""
            let cwd = terminal.workingDirectory.map { " \($0)" } ?? ""
            print("\(shortId): \(terminal.title) \(size)\(cwd)\(focused)".trimmingCharacters(in: .whitespaces))
        }
    }
}
