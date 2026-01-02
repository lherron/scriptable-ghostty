<!-- LOGO -->
<h1>
<p align="center">
  <img src="macos/Assets.xcassets/ScriptableGhosttyIcon.imageset/ScriptableGhostty-icon.png" alt="Logo" width="128">
  <br>Scriptable Ghostty
</h1>
  <p align="center">
    A fork of Ghostty adding scripting capabilities via API.
    <br />
    <a href="https://ghostty.org/docs">Ghostty Docs</a>
    ·
    <a href="https://github.com/ghostty-org/ghostty">Upstream Ghostty</a>
  </p>
</p>

## About

Scriptable Ghostty is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) that exposes the Ghostty command palette and app intents via API, exposed over HTTP and Unix sockets.

**macOS only.** The scripting API is implemented in Swift via the [Features/API](macos/Sources/Features/API/) module. See the [API Guide](macos/Sources/Features/API/API_GUIDE.md) for details.

## API Versions

| Version | Binding | Description |
| :-----: | ------- | ----------- |
| **v1** | Command Palette Actions | Scriptable actions exposed through the command palette |
| **v2** | App Intents | Interface to App Intents, surface used by Apple Shortcuts |

## API Transport

- **HTTP:** `http://127.0.0.1:<port>/api/v1` and `http://127.0.0.1:<port>/api/v2`
- **UDS:** `~/Library/Application Support/Ghostty/api.sock` (per-user)

UDS uses a 4-byte big-endian length prefix followed by a JSON payload. See
the API docs in `macos/Sources/Features/API/` for schema details.

## ghostmux (Experimental CLI)

`ghostmux` is a tiny, intentionally limited CLI to explore Ghostty automation. The command
surface is minimal and many tmux-style options are **not** implemented yet.

Supported commands:
- `list-surfaces` (alias: `ls`)
- `status`
- `new`
- `send-keys` (requires `-t <target>`)
- `set-title` (requires `-t <target>`)
- `capture-pane` (requires `-t <target>`, visible-only by default, `--selection` supported)

All commands accept `--json` for machine-readable output.

Examples:
```bash
# List terminals
ghostmux ls
# Example output:
ABCDEF12 /path/to/project (/path/to/project) [80x24] (focused)
1234ABCD /home/user (/home/user) [80x24]

# Send keys to a terminal
ghostmux send-keys -t ABCDEF12 "ls -la" --enter

# Set a terminal title
ghostmux set-title -t ABCDEF12 "build: ghostty"

# Create a new tab or window
ghostmux new --tab --cwd /tmp

# Check API availability
ghostmux status --json

# Capture visible pane contents to stdout
ghostmux capture-pane -t ABCDEF12

# Capture current selection
ghostmux capture-pane -t ABCDEF12 --selection
```

## Shell Environment

Scriptable Ghostty injects `GHOSTTY_SURFACE_UUID` into each shell session, containing the UUID of the terminal surface. This allows scripts to identify which surface they're running in and target API calls accordingly.

```bash
echo $GHOSTTY_SURFACE_UUID
# e.g., 550E8400-E29B-41D4-A716-446655440000
```

## Building

This fork uses a [Justfile](Justfile) to wrap the build process, keeping fork-specific customizations separate from upstream code for easier merges.

```bash
just build    # Build the app
just install  # Build and install to ~/Applications
just run      # Build and run without installing
just info     # Show build configuration
```

See upstream [HACKING.md](HACKING.md) for full build prerequisites.

**Note:** The Justfile uses ad-hoc signing by default. For better macOS integration (saved permissions, Accessibility access, etc.), create a `.env.local` file with your signing identity:

```bash
echo 'signing_identity="Apple Development: Your Name (TEAMID)"' > .env.local
```

## Upstream

This fork tracks upstream Ghostty. For documentation on terminal features, configuration, and general usage, see the [Ghostty documentation](https://ghostty.org/docs).

**Based on upstream commit:** [`6a1a4eee2`](https://github.com/ghostty-org/ghostty/commit/6a1a4eee2) (2025-12-30)
