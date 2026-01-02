import Foundation

struct SetTitleCommand: GhostmuxCommand {
    static let name = "set-title"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux set-title -t <target> <title>

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var positional: [String] = []
        var json = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]
            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "-h" || arg == "--help" {
                print(help)
                return
            }

            if arg == "--json" {
                json = true
                i += 1
                continue
            }

            positional.append(arg)
            i += 1
        }

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("set-title requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        let title = positional.joined(separator: " ")
        if title.isEmpty {
            throw GhostmuxError.message("set-title requires a title")
        }

        if title.contains("\u{1b}") || title.contains("\u{07}") {
            throw GhostmuxError.message("set-title does not allow escape or bell characters")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        do {
            try context.client.setTitle(terminalId: targetTerminal.id, title: title)
            if json {
                writeJSON(["success": true])
            }
            return
        } catch let error as GhostmuxError {
            switch error {
            case .apiError(let status, let message):
                if status == 404 || (message?.contains("Endpoint not found") ?? false) {
                    let command = oscPrintfCommand(title: title)
                    try context.client.sendText(terminalId: targetTerminal.id, text: command + "\n")
                    fputs("warning: /title endpoint unavailable; sent OSC via shell input\n", stderr)
                    return
                }
                throw error
            default:
                throw error
            }
        }
    }

    private static func oscPrintfCommand(title: String) -> String {
        let escaped = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "printf $'\\e]0;\(escaped)\\a'"
    }
}
