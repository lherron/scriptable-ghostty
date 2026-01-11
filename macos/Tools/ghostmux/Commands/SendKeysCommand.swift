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
      --no-enter            Don't send Enter after keys
      --json                Output JSON
      -h, --help            Show this help

    Note: An Enter key is sent after the keys by default.

    Text is sent using the native paste mechanism for reliability.
    Special keys (Enter, Tab, Escape, C-c, etc.) are sent as key events.
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var literal = false
        var noEnter = false
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

            if arg == "--no-enter" {
                noEnter = true
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

        if literal {
            // Literal mode: send all text using native input API
            let text = positional.joined(separator: " ")
            try context.client.sendText(terminalId: targetTerminal.id, text: text)
        } else {
            // Non-literal mode: use sendText for regular text, sendKey for special keys
            let hasSpecialKeys = positional.contains { specialKeyStroke(for: $0) != nil }

            if hasSpecialKeys {
                // Mixed input: send text chunks and special keys separately
                try sendTokens(positional, to: targetTerminal.id, client: context.client)
            } else {
                // Text only: send via native input API
                let text = positional.joined(separator: " ")
                try context.client.sendText(terminalId: targetTerminal.id, text: text)
            }
        }

        // Send Enter via /key endpoint (not /input's enter param) for TUI compatibility
        if !noEnter {
            usleep(200000)  // 200ms delay for TUI apps to process input
            let enterStroke = KeyStroke(key: "enter", mods: [], text: "\n", unshiftedCodepoint: 0x0A)
            try context.client.sendKey(terminalId: targetTerminal.id, stroke: enterStroke)
        }

        if json {
            writeJSON(["success": true])
        }
    }

    /// Send tokens using hybrid approach: sendText for regular text, sendKey for special keys
    private static func sendTokens(_ tokens: [String], to terminalId: String, client: GhostmuxClient) throws {
        var textBuffer = ""

        for token in tokens {
            if let specialKey = specialKeyStroke(for: token) {
                // Flush accumulated text before sending special key
                if !textBuffer.isEmpty {
                    try client.sendText(terminalId: terminalId, text: textBuffer)
                    textBuffer = ""
                }
                // Send special key using key event
                try client.sendKey(terminalId: terminalId, stroke: specialKey)
            } else {
                // Accumulate text (add space between tokens)
                if !textBuffer.isEmpty {
                    textBuffer += " "
                }
                textBuffer += token
            }
        }

        // Flush any remaining text
        if !textBuffer.isEmpty {
            try client.sendText(terminalId: terminalId, text: textBuffer)
        }
    }

    /// Returns a KeyStroke if the token is a special key that requires sendKey, nil otherwise
    private static func specialKeyStroke(for token: String) -> KeyStroke? {
        let lower = token.lowercased()

        // Named special keys (excluding space which can be sent as text)
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
                    return nil  // Invalid, treat as text
                }

                // Check if it's a control + named key
                if let named = namedKeys[remainder.lowercased()] {
                    return KeyStroke(
                        key: named.key,
                        mods: ["ctrl"] + named.mods,
                        text: nil,
                        unshiftedCodepoint: named.unshiftedCodepoint
                    )
                }

                // Check if it's a control + single character
                if remainder.count == 1, let scalar = remainder.unicodeScalars.first,
                   let base = keyStrokeForScalar(scalar) {
                    return KeyStroke(
                        key: base.key,
                        mods: ["ctrl"] + base.mods,
                        text: nil,
                        unshiftedCodepoint: base.unshiftedCodepoint
                    )
                }

                return nil  // Invalid control sequence, treat as text
            }
        }

        // Not a special key - will be sent as text
        return nil
    }
}
