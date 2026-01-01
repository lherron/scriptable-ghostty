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

Scriptable Ghostty is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) that exposes terminal functionality through scriptable APIs, enabling automation and integration with external tools.

**macOS only.** The scripting API is implemented in Swift via the [Features/API](macos/Sources/Features/API/) module. See the [API Guide](macos/Sources/Features/API/API_GUIDE.md) for details.

## API Versions

| Version | Binding | Description |
| :-----: | ------- | ----------- |
| **v1** | Command Palette Actions | Scriptable actions exposed through the command palette |
| **v2** | App Intents | Native Apple Shortcuts integration for system-wide automation |

## API Transport

- **HTTP:** `http://127.0.0.1:<port>/api/v1` and `http://127.0.0.1:<port>/api/v2`
- **UDS:** `~/Library/Application Support/Ghostty/api.sock` (per-user)

UDS uses a 4-byte big-endian length prefix followed by a JSON payload. See
the API docs in `macos/Sources/Features/API/` for schema details.

## ghostmux (UDS-only CLI)

`ghostmux` is a tiny, intentionally limited CLI that talks to the UDS API. The command
surface is minimal right now: only a handful of commands are supported and many
tmux-style options are **not** implemented yet.

Supported commands:
- `list-surfaces` (alias: `list-sessions`)
- `send-keys` (requires `-t <target>`)
- `set-title` (requires `-t <target>`)
- `capture-pane` (requires `-t <target>`, visible-only by default)

Note: `set-title` uses a direct API endpoint when available. If the app
doesn't support it yet, `ghostmux` falls back to sending an OSC sequence
via shell input (which requires a shell prompt and will appear in the buffer).

Examples:
```bash
# List terminals
ghostmux list-surfaces
# Example output:
1a2b3c4d: /Users/lherron [80x24] /Users/lherron (focused)
9f8e7d6c: /Users/lherron [80x24] /Users/lherron

# Send keys to a terminal
ghostmux send-keys -t 1a2b3c4d "ls -la" --enter

# Set a terminal title
ghostmux set-title -t 1a2b3c4d "build: ghostty"

# Capture visible pane contents to stdout
ghostmux capture-pane -t 1a2b3c4d
```

## Shell Environment

Scriptable Ghostty injects `GHOSTTY_SURFACE_UUID` into each shell session, containing the UUID of the terminal surface. This allows scripts to identify which surface they're running in and target API calls accordingly.

```bash
echo $GHOSTTY_SURFACE_UUID
# e.g., 550E8400-E29B-41D4-A716-446655440000
```

See [`SurfaceView_AppKit.swift:379`](macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift#L379) for implementation details.

## Building

This fork uses a [Justfile](Justfile) to wrap the build process, keeping fork-specific customizations separate from upstream code for easier updates.

```bash
just build    # Build the app
just install  # Build and install to ~/Applications
just run      # Build and run without installing
just info     # Show build configuration
```

Requires [just](https://github.com/casey/just), Xcode, and Zig. See upstream [HACKING.md](HACKING.md) for full build prerequisites.

**Note:** The Justfile uses ad-hoc signing by default. For better macOS integration (saved permissions, Accessibility access, etc.), create a `.env.local` file with your signing identity:

```bash
echo 'signing_identity="Apple Development: Your Name (TEAMID)"' > .env.local
```

## Upstream

This fork tracks upstream Ghostty. For documentation on terminal features, configuration, and general usage, see the [Ghostty documentation](https://ghostty.org/docs).

**Based on:** [`6a1a4eee2`](https://github.com/ghostty-org/ghostty/commit/6a1a4eee2) (2025-12-30)
