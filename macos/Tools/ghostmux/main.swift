#!/usr/bin/env swift
import Foundation

private let usage = """
ghostmux - Ghostty CLI (UDS only)

Usage:
  ghostmux <command> [options]

Commands:
  list-surfaces         List all terminals
  status                Check Ghostty API availability
  new                   Create a new terminal window or tab
  kill-surface          Close a terminal (requires -t)
  set-bg                Set terminal background color (requires -t)
  send-keys             Send keys + Enter to a terminal (requires -t)
  send-key              Send a key without Enter (requires -t)
  set-title             Set terminal title (requires -t)
  statusbar             Control the programmable status bar (requires -t)
  capture-pane, capturep  Capture pane contents (visible only by default)
  stream-surface, stream  Stream raw PTY output in real-time (requires -t)

Options:
  -h, --help            Show this help
  --json                Output JSON (command-specific)

Run `ghostmux <command> --help` for command-specific options.

Examples:
  ghostmux list-surfaces
  ghostmux status
  ghostmux new --tab --cwd /tmp
  ghostmux send-keys -t 1a2b3c4d "ls -la"
  ghostmux send-key -t 550e8400 C-c
  ghostmux set-title -t 1a2b3c4d "build: ghostty"
  ghostmux statusbar set -t 1a2b3c4d "left|center|right"
  ghostmux capture-pane -t 550e8400
  ghostmux capturep -t 550e8400 -S 0 -E 5
"""

private let commandTypes: [GhostmuxCommand.Type] = [
    ListSessionsCommand.self,
    StatusCommand.self,
    NewCommand.self,
    KillSurfaceCommand.self,
    SetBackgroundCommand.self,
    SendKeysCommand.self,
    SendKeyCommand.self,
    SetTitleCommand.self,
    StatusBarCommand.self,
    CapturePaneCommand.self,
    StreamSurfaceCommand.self,
]

func printUsage() {
    print(usage)
}

func resolveCommand(_ name: String) -> GhostmuxCommand.Type? {
    for command in commandTypes {
        if command.name == name || command.aliases.contains(name) {
            return command
        }
    }
    return nil
}

func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty {
        printUsage()
        return
    }

    if args[0] == "-h" || args[0] == "--help" {
        printUsage()
        return
    }

    let commandName = args[0]
    let commandArgs = Array(args.dropFirst())

    guard let command = resolveCommand(commandName) else {
        fputs("error: unknown command '\(commandName)'\n", stderr)
        fputs("run 'ghostmux --help' for usage\n", stderr)
        exit(1)
    }

    let client = GhostmuxClient(socketPath: defaultSocketPath())
    let context = CommandContext(args: commandArgs, client: client)

    do {
        try command.run(context: context)
    } catch let error as GhostmuxError {
        fputs("error: \(error.description)\n", stderr)
        exit(1)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

main()
