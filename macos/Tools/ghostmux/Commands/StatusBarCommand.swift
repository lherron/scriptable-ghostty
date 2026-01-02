import Foundation

struct StatusBarCommand: GhostmuxCommand {
    static let name = "statusbar"
    static let aliases: [String] = []
    static let help = """
    Usage:
      ghostmux statusbar set -t <target> "left|center|right"
      ghostmux statusbar show -t <target>
      ghostmux statusbar hide -t <target>
      ghostmux statusbar toggle -t <target>

      Use empty fields for blanks, e.g. "left||right"

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      --window              Apply to window fallback instead of surface
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var positional: [String] = []
        var json = false
        var windowScope = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]
            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--window" {
                windowScope = true
                i += 1
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

        guard let subcommand = positional.first else {
            throw GhostmuxError.message("statusbar requires a subcommand: set, show, hide, or toggle")
        }

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("statusbar requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        let scope = windowScope ? "window" : nil

        switch subcommand {
        case "set":
            let rawValue = positional.dropFirst().joined(separator: " ")
            if rawValue.isEmpty {
                throw GhostmuxError.message("statusbar set requires \"left|center|right\"")
            }

            let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                throw GhostmuxError.message("statusbar set requires exactly three fields: left|center|right")
            }

            let left = String(parts[0])
            let center = String(parts[1])
            let right = String(parts[2])

            try context.client.setStatusBar(
                terminalId: targetTerminal.id,
                left: left,
                center: center,
                right: right,
                visible: true,
                scope: scope
            )
        case "show":
            if positional.count > 1 {
                throw GhostmuxError.message("statusbar show does not take extra arguments")
            }
            try context.client.setStatusBar(terminalId: targetTerminal.id, visible: true, scope: scope)
        case "hide":
            if positional.count > 1 {
                throw GhostmuxError.message("statusbar hide does not take extra arguments")
            }
            try context.client.setStatusBar(terminalId: targetTerminal.id, visible: false, scope: scope)
        case "toggle":
            if positional.count > 1 {
                throw GhostmuxError.message("statusbar toggle does not take extra arguments")
            }
            try context.client.setStatusBar(terminalId: targetTerminal.id, toggle: true, scope: scope)
        default:
            throw GhostmuxError.message("unknown statusbar subcommand: \(subcommand)")
        }

        if json {
            writeJSON(["success": true])
        }
    }
}
