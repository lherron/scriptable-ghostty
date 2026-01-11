import Foundation

struct SendKeyCommand: GhostmuxCommand {
    static let name = "send-key"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux send-key -t <target> [options] <key>

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      -l, --literal         Send text literally (no special key handling)
      --json                Output JSON
      -h, --help            Show this help

    Send a key or text without pressing Enter afterward.
    Use send-keys (plural) if you want Enter sent automatically.

    Examples:
      ghostmux send-key -t 1a2b C-c          # Send Ctrl+C
      ghostmux send-key -t 1a2b Escape       # Send Escape
      ghostmux send-key -t 1a2b Tab          # Send Tab
      ghostmux send-key -t 1a2b "partial"    # Type text without Enter
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var literal = false
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
            throw GhostmuxError.message("send-key requires a key to send")
        }

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("send-key requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        if literal {
            // Literal mode: send all text using native input API
            let text = positional.joined(separator: " ")
            try context.client.sendText(terminalId: targetTerminal.id, text: text)
        } else {
            // Send each token - special keys via sendKey, text via sendText
            for token in positional {
                if let specialKey = specialKeyStroke(for: token) {
                    try context.client.sendKey(terminalId: targetTerminal.id, stroke: specialKey)
                } else {
                    try context.client.sendText(terminalId: targetTerminal.id, text: token)
                }
            }
        }

        // Never send Enter - that's the difference from send-keys

        if json {
            writeJSON(["success": true])
        }
    }

    /// Returns a KeyStroke if the token is a special key, nil otherwise
    private static func specialKeyStroke(for token: String) -> KeyStroke? {
        let lower = token.lowercased()

        let namedKeys: [String: KeyStroke] = [
            "enter": KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A),
            "return": KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A),
            "tab": KeyStroke(key: "tab", mods: [], text: "\t", unshiftedCodepoint: 0x09),
            "escape": KeyStroke(key: "escape", mods: [], text: nil, unshiftedCodepoint: 0),
            "esc": KeyStroke(key: "escape", mods: [], text: nil, unshiftedCodepoint: 0),
            "bspace": KeyStroke(key: "backspace", mods: [], text: nil, unshiftedCodepoint: 0),
            "backspace": KeyStroke(key: "backspace", mods: [], text: nil, unshiftedCodepoint: 0),
            "dc": KeyStroke(key: "delete", mods: [], text: nil, unshiftedCodepoint: 0),
            "delete": KeyStroke(key: "delete", mods: [], text: nil, unshiftedCodepoint: 0),
        ]

        if let named = namedKeys[lower] {
            return named
        }

        // Control key combinations (C-x, Ctrl-x)
        let ctrlPrefixes = ["c-", "ctrl-"]
        for prefix in ctrlPrefixes {
            if lower.hasPrefix(prefix) {
                let remainder = String(token.dropFirst(prefix.count))
                if remainder.isEmpty {
                    return nil
                }

                if let named = namedKeys[remainder.lowercased()] {
                    return KeyStroke(
                        key: named.key,
                        mods: ["ctrl"] + named.mods,
                        text: nil,
                        unshiftedCodepoint: named.unshiftedCodepoint
                    )
                }

                if remainder.count == 1, let scalar = remainder.unicodeScalars.first,
                   let base = keyStrokeForScalar(scalar) {
                    return KeyStroke(
                        key: base.key,
                        mods: ["ctrl"] + base.mods,
                        text: nil,
                        unshiftedCodepoint: base.unshiftedCodepoint
                    )
                }

                return nil
            }
        }

        return nil
    }
}
