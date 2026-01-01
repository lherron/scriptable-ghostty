import Foundation

struct CapturePaneCommand: GhostmuxCommand {
    static let name = "capture-pane"
    static let aliases = ["capturep"]
    static let help = """
    Usage:
      ghostmux capture-pane -t <target> [options]

    Options:
      -t <target>           Target terminal (UUID, title, or UUID prefix)
      -S <start>            Start line (0 = first visible line, - = history start)
      -E <end>              End line (0 = first visible line, - = visible end)
      --selection           Capture current selection text
      -p                    Print to stdout (default in ghostmux)
      --json                Output JSON
      -h, --help            Show this help
    """

    private enum LineSpec {
        case dash
        case value(Int)
    }

    static func run(context: CommandContext) throws {
        var target: String?
        var startSpec: LineSpec?
        var endSpec: LineSpec?
        var selection = false
        var json = false

        var i = 0
        while i < context.args.count {
            let arg = context.args[i]
            if arg == "-t", i + 1 < context.args.count {
                target = context.args[i + 1]
                i += 2
                continue
            }

            if arg == "-S", i + 1 < context.args.count {
                startSpec = try parseLineSpec(context.args[i + 1])
                i += 2
                continue
            }

            if arg == "-E", i + 1 < context.args.count {
                endSpec = try parseLineSpec(context.args[i + 1])
                i += 2
                continue
            }

            if arg == "--selection" {
                selection = true
                i += 1
                continue
            }

            if arg == "-p" {
                i += 1
                continue
            }

            if arg == "--json" {
                json = true
                i += 1
                continue
            }

            if arg == "-b", i + 1 < context.args.count {
                throw GhostmuxError.message("capture-pane buffers are not supported in ghostmux")
            }

            if arg == "-a" || arg == "-e" || arg == "-P" || arg == "-q" || arg == "-C" || arg == "-J" ||
                arg == "-M" || arg == "-N" || arg == "-T" {
                throw GhostmuxError.message("capture-pane flag not supported: \(arg)")
            }

            if arg == "-h" || arg == "--help" {
                print(help)
                return
            }

            throw GhostmuxError.message("unexpected argument: \(arg)")
        }

        guard let target else {
            throw GhostmuxError.message("capture-pane requires -t <target>")
        }

        let terminals = try context.client.listTerminals()
        guard let targetTerminal = resolveTarget(target, terminals: terminals) else {
            throw GhostmuxError.message("can't find terminal: \(target)")
        }

        if selection {
            if startSpec != nil || endSpec != nil {
                throw GhostmuxError.message("capture-pane --selection is not compatible with -S/-E")
            }
            let selectionText = try context.client.getSelectionContents(terminalId: targetTerminal.id)
            if json {
                let payload: [String: Any] = ["selection": selectionText ?? NSNull()]
                writeJSON(payload)
            } else if let selectionText {
                writeStdout(selectionText)
            }
            return
        }

        if startSpec == nil && endSpec == nil {
            let visible = try context.client.getVisibleContents(terminalId: targetTerminal.id)
            if json {
                writeJSON(["contents": visible])
            } else {
                writeStdout(visible)
            }
            return
        }

        let screen = try context.client.getScreenContents(terminalId: targetTerminal.id)
        let screenLines = splitLines(screen)
        if screenLines.isEmpty {
            return
        }

        let visibleLineCount = try resolveVisibleLineCount(
            terminal: targetTerminal,
            client: context.client
        )
        let visibleStart = max(0, screenLines.count - visibleLineCount)
        let visibleEnd = max(visibleStart, screenLines.count - 1)

        var startIndex = resolveStartIndex(spec: startSpec, visibleStart: visibleStart)
        var endIndex = resolveEndIndex(spec: endSpec, visibleStart: visibleStart, visibleEnd: visibleEnd)

        startIndex = clampIndex(startIndex, max: screenLines.count - 1)
        endIndex = clampIndex(endIndex, max: screenLines.count - 1)

        if endIndex < startIndex {
            return
        }

        let output = screenLines[startIndex...endIndex].joined(separator: "\n")
        if json {
            writeJSON(["contents": output])
        } else {
            writeStdout(output)
        }
    }

    private static func parseLineSpec(_ value: String) throws -> LineSpec {
        if value == "-" {
            return .dash
        }
        guard let parsed = Int(value) else {
            throw GhostmuxError.message("invalid line value: \(value)")
        }
        return .value(parsed)
    }

    private static func resolveVisibleLineCount(
        terminal: Terminal,
        client: GhostmuxClient
    ) throws -> Int {
        if let rows = terminal.rows, rows > 0 {
            return rows
        }
        let visible = try client.getVisibleContents(terminalId: terminal.id)
        return max(1, splitLines(visible).count)
    }

    private static func resolveStartIndex(spec: LineSpec?, visibleStart: Int) -> Int {
        switch spec {
        case nil:
            return visibleStart
        case .dash:
            return 0
        case .value(let value):
            return visibleStart + value
        }
    }

    private static func resolveEndIndex(spec: LineSpec?, visibleStart: Int, visibleEnd: Int) -> Int {
        switch spec {
        case nil:
            return visibleEnd
        case .dash:
            return visibleEnd
        case .value(let value):
            return visibleStart + value
        }
    }

    private static func clampIndex(_ index: Int, max: Int) -> Int {
        if max < 0 {
            return 0
        }
        return Swift.max(0, Swift.min(index, max))
    }

    private static func splitLines(_ text: String) -> [String] {
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    }
}
