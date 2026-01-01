import Foundation

struct NewCommand: GhostmuxCommand {
    static let name = "new"
    static let aliases = ["new-surface"]
    static let help = """
    Usage:
      ghostmux new [options]

    Options:
      --window              Create a new window (default)
      --tab                 Create a new tab
      --cwd <path>          Initial working directory
      --command <cmd>       Command to run after shell init
      --env <k=v>           Environment variable (repeatable)
      --parent <id>         Parent terminal UUID (for tabs)
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var location: String?
        var workingDirectory: String?
        var command: String?
        var env: [String: String] = [:]
        var parent: String?
        var json = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]

            if arg == "--window" {
                location = "window"
                i += 1
                continue
            }

            if arg == "--tab" {
                location = "tab"
                i += 1
                continue
            }

            if arg == "--cwd", i + 1 < context.args.count {
                workingDirectory = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--command", i + 1 < context.args.count {
                command = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--env", i + 1 < context.args.count {
                let pair = context.args[i + 1]
                guard let eqIndex = pair.firstIndex(of: "=") else {
                    throw GhostmuxError.message("env must be in KEY=VALUE form")
                }
                let key = String(pair[..<eqIndex])
                let value = String(pair[pair.index(after: eqIndex)...])
                if key.isEmpty {
                    throw GhostmuxError.message("env key must be non-empty")
                }
                env[key] = value
                i += 2
                continue
            }

            if arg == "--parent", i + 1 < context.args.count {
                parent = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--json" {
                json = true
                i += 1
                continue
            }

            if arg == "-h" || arg == "--help" {
                print(help)
                return
            }

            throw GhostmuxError.message("unexpected argument: \(arg)")
        }

        let request = CreateTerminalRequest(
            location: location,
            workingDirectory: workingDirectory,
            command: command,
            env: env.isEmpty ? nil : env,
            parent: parent
        )

        let terminal = try context.client.createTerminal(request: request)
        if json {
            writeJSON(terminal.toJsonDict())
            return
        }
        print(terminalSummary(terminal))
    }
}
