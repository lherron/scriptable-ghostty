import Foundation

struct KillSurfaceCommand: GhostmuxCommand {
    static let name = "kill-surface"
    static let aliases = ["close-surface", "delete-surface"]
    static let help = """
    Usage:
      ghostmux kill-surface -t <target> [options]

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
                            Falls back to $GHOSTTY_SURFACE_UUID if not specified
      --confirm             Show confirmation dialog
      --force               Bypass confirmation dialog
      --json                Output JSON
      -h, --help            Show this help
    """

    static func run(context: CommandContext) throws {
        var target: String?
        var confirm = false
        var force = false
        var json = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]
            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "--confirm" {
                confirm = true
                i += 1
                continue
            }

            if arg == "--force" {
                force = true
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

            throw GhostmuxError.message("unexpected argument: \(arg)")
        }

        let resolvedTarget: String
        if let target {
            resolvedTarget = target
        } else if let envTarget = ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_UUID"] {
            resolvedTarget = envTarget
        } else {
            throw GhostmuxError.message("kill-surface requires -t <target> or $GHOSTTY_SURFACE_UUID")
        }

        if confirm && force {
            throw GhostmuxError.message("kill-surface does not allow both --confirm and --force")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(resolvedTarget, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(resolvedTarget)")
        }

        try context.client.deleteTerminal(terminalId: targetTerminal.id, confirm: confirm && !force)
        if json {
            writeJSON(["success": true])
        }
    }
}
