import Foundation

struct StatusCommand: GhostmuxCommand {
    static let name = "status"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux status

    Options:
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var json = false
        for arg in context.args {
            if arg == "-h" || arg == "--help" {
                print(help)
                return
            }
            if arg == "--json" {
                json = true
                continue
            }
            throw GhostmuxError.message("unexpected argument: \(arg)")
        }

        let available = context.client.isAvailable()
        if json {
            writeJSON(["available": available])
            return
        }
        print("available: \(available)")
    }
}
