import Foundation

struct SendKeysCommand: GhostmuxCommand {
    static let name = "send-keys"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux send-keys -t <target> [options] <keys>...

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
      -l, --literal         Send keys literally (no special handling)
      --enter               Press Enter after sending text
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var literal = false
        var enter = false
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

        guard let target else {
            throw GhostmuxError.message("send-keys requires -t <target>")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(target, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(target)")
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
    }
}
