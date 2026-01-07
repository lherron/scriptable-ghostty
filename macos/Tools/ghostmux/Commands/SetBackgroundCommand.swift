import Foundation

struct SetBackgroundCommand: GhostmuxCommand {
    static let name = "set-bg"
    static let aliases = ["set-background", "bg"]
    static let help = """
    Usage:
      ghostmux set-bg -t <target> [options] <hex>

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      --color <hex>         Background color (#RRGGBB or RRGGBB)
      --reset               Reset background to default (OSC 111)
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var color: String?
        var reset = false
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

            if arg == "--color", i + 1 < context.args.count {
                color = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--reset" {
                reset = true
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

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("set-bg requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        if reset {
            if color != nil || !positional.isEmpty {
                throw GhostmuxError.message("set-bg --reset cannot be combined with a color")
            }
        } else {
            if color == nil {
                if positional.count == 1 {
                    color = positional[0]
                } else if positional.isEmpty {
                    throw GhostmuxError.message("set-bg requires a color or --reset")
                } else {
                    throw GhostmuxError.message("set-bg expects a single color value")
                }
            }
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        if reset {
            try context.client.sendOutput(terminalId: targetTerminal.id, data: oscResetBackground())
        } else {
            guard let color, let hex = normalizeHex(color) else {
                throw GhostmuxError.message("set-bg expects a hex color like #RRGGBB")
            }
            try context.client.sendOutput(terminalId: targetTerminal.id, data: oscSetBackground(hex: hex))
        }

        if json {
            writeJSON(["success": true])
        }
    }

    private static func oscSetBackground(hex: String) -> String {
        "\u{1b}]11;\(hex)\u{07}"
    }

    private static func oscResetBackground() -> String {
        "\u{1b}]111\u{07}"
    }

    private static func normalizeHex(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        let expanded: String
        switch value.count {
        case 3:
            expanded = value.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = value
        default:
            return nil
        }

        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard expanded.unicodeScalars.allSatisfy({ hexSet.contains($0) }) else {
            return nil
        }

        return "#\(expanded.lowercased())"
    }
}
