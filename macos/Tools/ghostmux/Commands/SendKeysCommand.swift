import Foundation

struct SendKeysCommand: GhostmuxCommand {
    static let name = "send-keys"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux send-keys -t <target> [options] <keys>...

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      -l, --literal         Send keys literally (no special handling)
      --enter               Press Enter after sending text
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var literal = false
        var enter = false
        var json = false
        var positional: [String] = []

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]
            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "-l" || arg == "--literal" {
                literal = true
                i += 1
                continue
            }

            if arg == "--enter" {
                enter = true
                i += 1
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

            positional.append(arg)
            i += 1
        }

        if positional.isEmpty {
            throw GhostmuxError.message("send-keys requires keys to send")
        }

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("send-keys requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        var strokes: [KeyStroke] = []
        if literal {
            let text = positional.joined(separator: " ")
            strokes.append(contentsOf: try strokesForLiteral(text))
        } else {
            for token in positional {
                strokes.append(contentsOf: try strokesForToken(token))
            }
        }

        if enter {
            strokes.append(KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A))
        }

        for stroke in strokes {
            try context.client.sendKey(terminalId: targetTerminal.id, stroke: stroke)
        }

        if json {
            writeJSON(["success": true])
        }
    }
}
