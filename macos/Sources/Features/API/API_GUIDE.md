# Ghostty REST API Integration Guide

This guide provides comprehensive documentation for integrating with Ghostty's REST API, enabling programmatic control of terminal surfaces from external tools, scripts, and editor plugins.

## Table of Contents

- [Overview](#overview)
- [Configuration](#configuration)
- [API Endpoints](#api-endpoints)
  - [API v1](#api-v1)
  - [API v2](#api-v2)
- [Action Reference](#action-reference)
- [Common Integration Patterns](#common-integration-patterns)
- [Error Handling](#error-handling)

---

## Overview

The Ghostty REST API provides HTTP-based control over terminal surfaces. Use it to:

- List and query terminal panes/splits
- Execute keybinding actions programmatically
- Read screen contents
- Send text and keystrokes to specific terminals
- Build custom command palettes, editor integrations, or automation tools

The API is versioned. v1 is legacy; v2 is intent-driven and recommended for new integrations.

### Quickstart (v2)

```bash
# Check if the v2 API is running
curl http://localhost:19999/api/v2/

# List all terminals
curl http://localhost:19999/api/v2/terminals

# Create a new terminal tab
curl -X POST http://localhost:19999/api/v2/terminals \
  -H "Content-Type: application/json" \
  -d '{
    "location": "tab",
    "working_directory": "/Users/demo/projects",
    "command": "npm run dev"
  }'

# Send text and press Enter
curl -X POST http://localhost:19999/api/v2/terminals/{id}/input \
  -H "Content-Type: application/json" \
  -d '{"text": "git status", "enter": true}'
```

### Quickstart (ghostmux CLI)

For shell scripting and tmux-like workflows, use `ghostmux`:

```bash
# List terminals
ghostmux list-surfaces

# Send keys to a terminal
ghostmux send-keys -t 550e8400 "ls -la" --enter

# Stream real-time PTY output
ghostmux stream -t 550e8400

# Capture pane contents
ghostmux capture-pane -t 550e8400
```

### Quickstart (v1)

```bash
# Check if the API is running
curl http://localhost:19999/

# List all terminal surfaces
curl http://localhost:19999/api/v1/surfaces

# Get the focused surface
curl http://localhost:19999/api/v1/surfaces/focused

# Send text to a specific surface
curl -X POST http://localhost:19999/api/v1/surfaces/{uuid}/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "text:hello\\n"}'
```

---

## Configuration

The API server is controlled by two configuration options in your Ghostty config file (`~/.config/ghostty/config` or equivalent):

### `macos-api-server`

Enable or disable the REST API server.

```ini
# Enable the API server (default: true)
macos-api-server = true

# Disable the API server
macos-api-server = false
```

### `macos-api-server-port`

Set the port number for the API server.

```ini
# Default port
macos-api-server-port = 19999

# Custom port
macos-api-server-port = 8080
```

### Security Notes

- The server binds to `127.0.0.1` (localhost) only
- No authentication is required - any local process can access the API
- The API cannot be accessed from remote machines

---

## API Endpoints

All endpoints return JSON responses. The base URL is `http://localhost:19999`.

- v1 endpoints are under `/api/v1`
- v2 endpoints are under `/api/v2`

### API v1

### GET /

Returns basic API information and available endpoints.

**Request:**
```bash
curl http://localhost:19999/
```

**Response:**
```json
{
  "version": "1",
  "endpoints": [
    "GET /api/v1/surfaces",
    "GET /api/v1/surfaces/focused",
    "GET /api/v1/surfaces/{uuid}",
    "GET /api/v1/surfaces/{uuid}/commands",
    "GET /api/v1/surfaces/{uuid}/screen",
    "POST /api/v1/surfaces/{uuid}/actions"
  ]
}
```

---

### GET /api/v1/surfaces

List all terminal surfaces (windows, tabs, splits).

**Request:**
```bash
curl http://localhost:19999/api/v1/surfaces
```

**Response:**
```json
{
  "surfaces": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "zsh",
      "workingDirectory": "/Users/demo/projects",
      "focused": true,
      "columns": 120,
      "rows": 40,
      "cellWidth": 10,
      "cellHeight": 20
    },
    {
      "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "title": "vim",
      "workingDirectory": "/Users/demo/projects",
      "focused": false,
      "columns": 80,
      "rows": 24,
      "cellWidth": 10,
      "cellHeight": 20
    }
  ]
}
```

**Surface Object Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID identifying the surface |
| `title` | string | Terminal title (often shell or running command) |
| `workingDirectory` | string | Current working directory |
| `focused` | boolean | Whether this surface has keyboard focus |
| `columns` | integer | Terminal width in columns |
| `rows` | integer | Terminal height in rows |
| `cellWidth` | integer | Cell width in pixels |
| `cellHeight` | integer | Cell height in pixels |

---

### GET /api/v1/surfaces/focused

Get the currently focused surface.

**Request:**
```bash
curl http://localhost:19999/api/v1/surfaces/focused
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "zsh",
  "workingDirectory": "/Users/demo/projects",
  "focused": true,
  "columns": 120,
  "rows": 40,
  "cellWidth": 10,
  "cellHeight": 20
}
```

**Error Response (no focused surface):**
```json
{
  "error": "No focused surface"
}
```

---

### GET /api/v1/surfaces/{uuid}

Get a specific surface by UUID.

**Request:**
```bash
curl http://localhost:19999/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "zsh",
  "workingDirectory": "/Users/demo/projects",
  "focused": true,
  "columns": 120,
  "rows": 40,
  "cellWidth": 10,
  "cellHeight": 20
}
```

---

### GET /api/v1/surfaces/{uuid}/commands

List available commands for a surface. These are the actions that can be executed via the command palette or keybindings.

**Request:**
```bash
curl http://localhost:19999/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000/commands
```

**Response:**
```json
{
  "commands": [
    {
      "actionKey": "new_window",
      "action": "new_window",
      "title": "New Window",
      "description": "Open a new terminal window"
    },
    {
      "actionKey": "new_tab",
      "action": "new_tab",
      "title": "New Tab",
      "description": "Open a new tab"
    }
  ]
}
```

---

### GET /api/v1/surfaces/{uuid}/screen

Get the current screen contents of a surface.

**Request:**
```bash
curl http://localhost:19999/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000/screen
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "contents": "user@host:~/projects$ ls\nfile1.txt  file2.txt  src/\nuser@host:~/projects$ "
}
```

---

### POST /api/v1/surfaces/{uuid}/actions

Execute an action on a specific surface.

**Request:**
```bash
curl -X POST http://localhost:19999/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "new_tab"}'
```

**Request Body:**
```json
{
  "action": "action_name"
}
```

**Success Response:**
```json
{
  "success": true,
  "action": "new_tab"
}
```

**Failure Response:**
```json
{
  "success": false,
  "action": "invalid_action",
  "error": "Action failed or not recognized"
}
```

---

### API v2

The v2 API maps to App Intents and uses `snake_case` field names. Base URL: `http://localhost:19999/api/v2`.

#### GET /api/v2/

Returns API version and available endpoints.

**Request:**
```bash
curl http://localhost:19999/api/v2/
```

**Response:**
```json
{
  "version": "2",
  "endpoints": [
    "GET /api/v2/terminals",
    "GET /api/v2/terminals/focused",
    "GET /api/v2/terminals/{id}",
    "POST /api/v2/terminals",
    "DELETE /api/v2/terminals/{id}",
    "POST /api/v2/terminals/{id}/focus",
    "POST /api/v2/terminals/{id}/input",
    "POST /api/v2/terminals/{id}/output",
    "POST /api/v2/terminals/{id}/statusbar",
    "POST /api/v2/terminals/{id}/action",
    "POST /api/v2/terminals/{id}/key",
    "POST /api/v2/terminals/{id}/mouse/button",
    "POST /api/v2/terminals/{id}/mouse/position",
    "POST /api/v2/terminals/{id}/mouse/scroll",
    "GET /api/v2/terminals/{id}/screen",
    "GET /api/v2/terminals/{id}/details/{type}",
    "POST /api/v2/quick-terminal",
    "GET /api/v2/commands"
  ]
}
```

---

#### GET /api/v2/terminals

List all terminals.

**Request:**
```bash
curl http://localhost:19999/api/v2/terminals
```

**Response:**
```json
{
  "terminals": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "zsh",
      "working_directory": "/Users/demo/projects",
      "kind": "normal",
      "focused": true,
      "columns": 120,
      "rows": 40,
      "cell_width": 10,
      "cell_height": 20
    }
  ]
}
```

**Terminal Object Fields (v2):**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID identifying the terminal |
| `title` | string | Terminal title (often shell or running command) |
| `working_directory` | string? | Current working directory |
| `kind` | string | `"normal"` or `"quick"` |
| `focused` | boolean | Whether this terminal has keyboard focus |
| `columns` | integer | Terminal width in columns |
| `rows` | integer | Terminal height in rows |
| `cell_width` | integer | Cell width in pixels |
| `cell_height` | integer | Cell height in pixels |

---

#### GET /api/v2/terminals/focused

Get the currently focused terminal.

**Request:**
```bash
curl http://localhost:19999/api/v2/terminals/focused
```

**Response:** Terminal object (see above)

**Error Response (no focused terminal):**
```json
{
  "error": "no_focused_terminal",
  "message": "No terminal is currently focused"
}
```

---

#### GET /api/v2/terminals/{id}

Get a specific terminal by UUID.

**Request:**
```bash
curl http://localhost:19999/api/v2/terminals/550e8400-e29b-41d4-a716-446655440000
```

**Response:** Terminal object (see above)

---

#### POST /api/v2/terminals

Create a new terminal window, tab, or split.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `location` | string | No | `"window"` (default), `"tab"`, `"split:left"`, `"split:right"`, `"split:up"`, `"split:down"` |
| `command` | string | No | Command to execute after shell initialization |
| `working_directory` | string | No | Initial working directory path |
| `env` | object | No | Environment variables as key-value pairs |
| `parent` | string | No | UUID of parent terminal (for tabs/splits) |

**Example:**
```json
{
  "location": "tab",
  "working_directory": "/Users/demo/projects/myapp",
  "command": "npm run dev",
  "env": {
    "NODE_ENV": "development"
  }
}
```

**Response:** Terminal object (see above)

**Notes:**
- `command` is converted to `initialInput` with `; exit\n`, so the shell exits when the command completes
- For splits, if no `parent` is provided, the focused terminal is used

---

#### DELETE /api/v2/terminals/{id}

Close a terminal.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `confirm` | boolean | `false` | Whether to show confirmation dialog |

**Response:**
```json
{
  "success": true
}
```

**Notes:**
- `scope: "surface"` overrides any window fallback for that terminal

---

#### POST /api/v2/terminals/{id}/focus

Focus a specific terminal, bringing its window to the front.

**Response:**
```json
{
  "success": true
}
```

---

#### POST /api/v2/terminals/{id}/input

Send text input to a terminal (like pasting).

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | string | Yes | Text to input |
| `enter` | boolean | No | Send Enter key after input |

**Example:**
```json
{
  "text": "git status",
  "enter": true
}
```

**Response:**
```json
{
  "success": true
}
```

**Notes:**
- Text is sent as-if pasted, no escape sequence parsing
- For control characters or key events, use the `/key` endpoint instead

---

#### POST /api/v2/terminals/{id}/output

Send output bytes to a terminal, processed as if they were read from the pty.

**Request Body:**
```json
{
  "data": "..."
}
```

**Notes:**
- Use this for terminal control sequences (OSC/CSI) without going through the shell.
- Include escape bytes directly in the JSON string (e.g. `\u001b` for ESC, `\u0007` for BEL).

---

#### POST /api/v2/terminals/{id}/statusbar

Set the programmable status bar for a terminal.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `left` | string | No | Left text |
| `center` | string | No | Center text |
| `right` | string | No | Right text |
| `visible` | boolean | No | Show/hide the status bar |
| `toggle` | boolean | No | Toggle visibility (takes precedence over `visible`) |
| `scope` | string | No | `surface` (default) or `window` for per-window fallback |

**Example:**
```json
{
  "left": "branch: main",
  "center": "build 123",
  "right": "OK",
  "visible": true
}
```

**Response:**
```json
{
  "success": true
}
```

---

#### POST /api/v2/terminals/{id}/action

Execute a keybind action on a terminal.

**Request Body:**
```json
{
  "action": "new_split:right"
}
```

**Response:**
```json
{
  "success": true,
  "action": "new_split:right"
}
```

**Notes:**
- Action strings match the v1 action reference and the keybind actions in your config
- Use `GET /api/v2/commands` to enumerate available actions

---

#### POST /api/v2/terminals/{id}/key

Send a keyboard event to simulate key presses.

**Request Body:**
```json
{
  "key": "enter",
  "mods": ["control"],
  "action": "press"
}
```

**Key Names:**
`a`-`z`, `0`-`9`, `enter`, `escape`, `tab`, `space`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `home`, `end`, `page_up`, `page_down`, `f1`-`f24`

**Modifier Keys:** `shift`, `control`, `option`, `command`

**Key Actions:** `press`, `release`, `repeat`

---

#### POST /api/v2/terminals/{id}/mouse/button

Send a mouse button event.

**Request Body:**
```json
{
  "button": "left",
  "action": "press",
  "mods": ["control"]
}
```

---

#### POST /api/v2/terminals/{id}/mouse/position

Send a mouse position/movement event.

**Request Body:**
```json
{
  "x": 150.0,
  "y": 200.0
}
```

**Notes:**
- Coordinates are passed through to the Ghostty App Intent used by Shortcuts; use the same coordinate space and units as Shortcuts

---

#### POST /api/v2/terminals/{id}/mouse/scroll

Send a mouse scroll event.

**Request Body:**
```json
{
  "y": -3.0,
  "precision": false,
  "momentum": "changed"
}
```

**Momentum Values:** `none`, `began`, `changed`, `ended`, `cancelled`, `stationary`

**Notes:**
- Scroll deltas and momentum values are passed through to the Ghostty App Intent used by Shortcuts

---

#### GET /api/v2/terminals/{id}/screen

Get the full screen contents including scrollback.

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "contents": "user@host:~/projects$ ls\\nfile1.txt  file2.txt  src/\\nuser@host:~/projects$ "
}
```

---

#### GET /api/v2/terminals/{id}/details/{type}

Get specific details about a terminal.

**Detail Types:** `title`, `working_directory`, `contents`, `selection`, `visible`

**Response:**
```json
{
  "type": "selection",
  "value": "selected text here"
}
```

---

#### POST /api/v2/quick-terminal

Open the quick/dropdown terminal. If already open, does nothing.

**Response:**
```json
{
  "terminals": [
    {
      "id": "...",
      "title": "zsh",
      "kind": "quick"
    }
  ]
}
```

---

#### GET /api/v2/commands

List all available command palette commands.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `terminal` | string | UUID of terminal to validate context |

**Response:**
```json
{
  "commands": [
    {
      "action_key": "new_window",
      "action": "new_window",
      "title": "New Window",
      "description": "Open a new terminal window"
    }
  ]
}
```

---

## Action Reference

Actions are executed via `POST /api/v1/surfaces/{uuid}/actions`. The `action` field in the request body specifies which action to perform.

### Text Input Actions

#### `text:VALUE`

Send text to the terminal. Uses Zig string literal escape syntax.

**Escape Sequences:**

| Escape | Character | Description |
|--------|-----------|-------------|
| `\\n` | LF | Newline / Enter |
| `\\r` | CR | Carriage return |
| `\\t` | TAB | Tab |
| `\\x00`-`\\xFF` | byte | Hex byte value |
| `\\\\` | `\` | Literal backslash |

**Examples:**

```bash
# Send "hello" and press Enter
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:hello\\n"}'

# Run a command
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:ls -la\\n"}'

# Send Ctrl+C (interrupt, ASCII 0x03)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:\\x03"}'

# Send Ctrl+D (EOF, ASCII 0x04)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:\\x04"}'

# Send Ctrl+Z (suspend, ASCII 0x1A)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:\\x1a"}'

# Send Escape key (ASCII 0x1B)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:\\x1b"}'

# Send Tab
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "text:\\t"}'
```

---

#### `csi:VALUE`

Send a CSI (Control Sequence Introducer) escape sequence. The CSI prefix (`ESC [` or `\x1b[`) is automatically added.

```bash
# Cursor up (CSI A)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:A"}'

# Cursor down (CSI B)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:B"}'

# Cursor forward/right (CSI C)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:C"}'

# Cursor back/left (CSI D)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:D"}'

# Move cursor to row 10, column 5 (CSI 10;5H)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:10;5H"}'

# Clear screen (CSI 2J)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:2J"}'

# Reset text attributes (CSI 0m)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "csi:0m"}'
```

---

#### `esc:VALUE`

Send an ESC sequence. The ESC prefix (`\x1b`) is automatically added.

```bash
# Example ESC sequence
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "esc:c"}'
```

---

### Terminal Actions

#### `reset`

Reset the terminal to its initial state. Equivalent to running the `reset` command.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "reset"}'
```

---

#### `clear_screen`

Clear the screen and all scrollback history.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "clear_screen"}'
```

---

### Clipboard Actions

#### `copy_to_clipboard`

Copy the currently selected text to the clipboard.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "copy_to_clipboard"}'
```

---

#### `paste_from_clipboard`

Paste the contents of the system clipboard into the terminal.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "paste_from_clipboard"}'
```

---

#### `paste_from_selection`

Paste the contents of the selection clipboard (X11 primary selection).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "paste_from_selection"}'
```

---

#### `copy_url_to_clipboard`

If there's a URL under the cursor, copy it to the clipboard.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "copy_url_to_clipboard"}'
```

---

#### `copy_title_to_clipboard`

Copy the terminal title to the clipboard.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "copy_title_to_clipboard"}'
```

---

### Font Actions

#### `increase_font_size:N`

Increase font size by N points.

```bash
# Increase by 1 point
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "increase_font_size:1"}'

# Increase by 2.5 points
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "increase_font_size:2.5"}'
```

---

#### `decrease_font_size:N`

Decrease font size by N points.

```bash
# Decrease by 1 point
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "decrease_font_size:1"}'
```

---

#### `reset_font_size`

Reset font size to the configured default.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "reset_font_size"}'
```

---

#### `set_font_size:N`

Set font size to exactly N points.

```bash
# Set to 14 points
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "set_font_size:14"}'
```

---

### Selection Actions

#### `select_all`

Select all text on the screen.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "select_all"}'
```

---

#### `adjust_selection:DIRECTION`

Adjust the current selection. Does nothing if no selection exists.

**Valid directions:** `left`, `right`, `up`, `down`, `page_up`, `page_down`, `home`, `end`, `beginning_of_line`, `end_of_line`

```bash
# Extend selection right
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "adjust_selection:right"}'

# Extend selection to end of line
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "adjust_selection:end_of_line"}'

# Extend selection to top of screen
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "adjust_selection:home"}'
```

---

### Search Actions

#### `start_search`

Open the search UI.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "start_search"}'
```

---

#### `search:TEXT`

Start a search for the specified text.

```bash
# Search for "error"
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "search:error"}'
```

---

#### `navigate_search:DIRECTION`

Navigate through search results.

**Valid directions:** `previous`, `next`

```bash
# Go to next match
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "navigate_search:next"}'

# Go to previous match
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "navigate_search:previous"}'
```

---

#### `end_search`

End the current search and hide the search UI.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "end_search"}'
```

---

### Scroll Actions

#### `scroll_to_top`

Scroll to the top of the scrollback buffer.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_to_top"}'
```

---

#### `scroll_to_bottom`

Scroll to the bottom (most recent output).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_to_bottom"}'
```

---

#### `scroll_to_selection`

Scroll to bring the current selection into view.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_to_selection"}'
```

---

#### `scroll_to_row:N`

Scroll to a specific row (0-indexed from top of scrollback).

```bash
# Scroll to row 100
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_to_row:100"}'
```

---

#### `scroll_page_up`

Scroll up by one page.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_up"}'
```

---

#### `scroll_page_down`

Scroll down by one page.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_down"}'
```

---

#### `scroll_page_fractional:N`

Scroll by a fraction of a page. Positive values scroll down, negative scroll up.

```bash
# Scroll down half a page
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_fractional:0.5"}'

# Scroll up 1.5 pages
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_fractional:-1.5"}'
```

---

#### `scroll_page_lines:N`

Scroll by N lines. Positive values scroll down, negative scroll up.

```bash
# Scroll down 5 lines
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_lines:5"}'

# Scroll up 10 lines
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "scroll_page_lines:-10"}'
```

---

#### `jump_to_prompt:N`

Jump forward or backward by N shell prompts. Requires shell integration.

```bash
# Jump to previous prompt
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "jump_to_prompt:-1"}'

# Jump forward 2 prompts
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "jump_to_prompt:2"}'
```

---

### File Export Actions

#### `write_scrollback_file:MODE`

Write the entire scrollback buffer to a temporary file.

**Valid modes:** `copy` (copy path to clipboard), `paste` (paste path into terminal), `open` (open in default editor)

```bash
# Copy scrollback to file and get path in clipboard
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "write_scrollback_file:copy"}'

# Open scrollback in default editor
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "write_scrollback_file:open"}'
```

---

#### `write_screen_file:MODE`

Write the visible screen contents to a temporary file.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "write_screen_file:copy"}'
```

---

#### `write_selection_file:MODE`

Write the selected text to a temporary file.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "write_selection_file:open"}'
```

---

### Window Actions

#### `new_window`

Open a new terminal window.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "new_window"}'
```

---

#### `close_window`

Close the current window and all its tabs/splits.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "close_window"}'
```

---

#### `reset_window_size`

Reset window to default size (macOS only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "reset_window_size"}'
```

---

#### `toggle_maximize`

Toggle window maximization (Linux only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_maximize"}'
```

---

#### `toggle_fullscreen`

Toggle fullscreen mode.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_fullscreen"}'
```

---

#### `toggle_window_decorations`

Toggle window decorations/titlebar (Linux only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_window_decorations"}'
```

---

#### `toggle_window_float_on_top`

Toggle always-on-top mode (macOS only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_window_float_on_top"}'
```

---

#### `toggle_visibility`

Show or hide all Ghostty windows (macOS only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_visibility"}'
```

---

### Tab Actions

#### `new_tab`

Open a new tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "new_tab"}'
```

---

#### `close_tab`

Close the current tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "close_tab"}'
```

---

#### `previous_tab`

Switch to the previous tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "previous_tab"}'
```

---

#### `next_tab`

Switch to the next tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "next_tab"}'
```

---

#### `last_tab`

Switch to the last tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "last_tab"}'
```

---

#### `goto_tab:N`

Switch to tab N (1-indexed). If N exceeds the tab count, goes to the last tab.

```bash
# Go to first tab
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "goto_tab:1"}'

# Go to third tab
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "goto_tab:3"}'
```

---

#### `move_tab:N`

Move the current tab by N positions. Wraps around cyclically.

```bash
# Move tab forward one position
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "move_tab:1"}'

# Move tab backward one position
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "move_tab:-1"}'
```

---

#### `toggle_tab_overview`

Toggle the tab overview (Linux with libadwaita 1.4+).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_tab_overview"}'
```

---

### Split Actions

#### `new_split:DIRECTION`

Create a new split in the specified direction.

**Valid directions:** `right`, `down`, `left`, `up`, `auto` (splits along the larger dimension)

```bash
# Split to the right
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "new_split:right"}'

# Split downward
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "new_split:down"}'

# Auto-split based on current dimensions
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "new_split:auto"}'
```

---

#### `goto_split:DIRECTION`

Focus on a split in the specified direction.

**Valid directions:** `previous`, `next`, `up`, `left`, `down`, `right`

```bash
# Focus split to the right
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "goto_split:right"}'

# Focus next split (in creation order)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "goto_split:next"}'
```

---

#### `toggle_split_zoom`

Zoom the current split to fill the entire tab area, hiding other splits.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_split_zoom"}'
```

---

#### `resize_split:DIRECTION,AMOUNT`

Resize the current split. Direction and pixel amount are comma-separated.

```bash
# Expand upward by 50 pixels
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "resize_split:up,50"}'

# Shrink from the right by 30 pixels
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "resize_split:right,-30"}'
```

---

#### `equalize_splits`

Equalize the size of all splits in the current tab.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "equalize_splits"}'
```

---

#### `close_surface`

Close the current surface (split, tab, or window depending on context).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "close_surface"}'
```

---

### Inspector & Debug Actions

#### `inspector:MODE`

Control the terminal inspector.

**Valid modes:** `toggle`, `show`, `hide`

```bash
# Toggle inspector
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "inspector:toggle"}'

# Show inspector
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "inspector:show"}'
```

---

#### `show_gtk_inspector`

Show the GTK inspector (Linux only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "show_gtk_inspector"}'
```

---

### Configuration Actions

#### `open_config`

Open the Ghostty configuration file in the default editor.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "open_config"}'
```

---

#### `reload_config`

Reload the configuration file and apply changes.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "reload_config"}'
```

---

### UI Actions

#### `toggle_command_palette`

Toggle the command palette (Linux requires libadwaita 1.5+).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_command_palette"}'
```

---

#### `prompt_surface_title`

Show a dialog to change the surface title (Linux requires libadwaita 1.5+).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "prompt_surface_title"}'
```

---

#### `toggle_quick_terminal`

Toggle the quick/drop-down terminal.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_quick_terminal"}'
```

---

### Security Actions

#### `toggle_secure_input`

Toggle secure input mode to prevent other apps from monitoring keystrokes (macOS only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_secure_input"}'
```

---

#### `toggle_mouse_reporting`

Toggle mouse event reporting to terminal applications.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "toggle_mouse_reporting"}'
```

---

### Undo/Redo Actions (macOS only)

#### `undo`

Undo the last undoable action (close tab, close split, etc.).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "undo"}'
```

---

#### `redo`

Redo the last undone action.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "redo"}'
```

---

### Application Actions

#### `check_for_updates`

Check for Ghostty updates (macOS only).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "check_for_updates"}'
```

---

#### `quit`

Quit Ghostty.

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "quit"}'
```

---

#### `crash:THREAD`

Trigger a hard crash for testing crash reporting. **WARNING: This will crash Ghostty and data may be lost.**

**Valid threads:** `main`, `io`, `render`

```bash
# Crash on main thread (DO NOT USE IN PRODUCTION)
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "crash:main"}'
```

---

### Keyboard Actions

#### `cursor_key`

Send data to the pty depending on cursor key mode. This is an advanced action primarily used internally for arrow key handling.

---

#### `show_on_screen_keyboard`

Show the on-screen keyboard (Linux only, requires accessibility settings).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "show_on_screen_keyboard"}'
```

---

### Deprecated Actions

#### `close_all_windows`

**DEPRECATED:** This action has no effect. Use `all:close_window` keybind prefix instead.

---

### Special Actions

#### `ignore`

Ignore the action (no-op).

```bash
curl -X POST http://localhost:19999/api/v1/surfaces/$UUID/actions \
  -d '{"action": "ignore"}'
```

---

#### `unbind`

Unbind a key combination (primarily for keybind configuration, not API use).

---

## Common Integration Patterns

### Run a Command in the Focused Terminal

```bash
#!/bin/bash
# run-in-ghostty.sh - Run a command in the focused Ghostty terminal

COMMAND="$1"
UUID=$(curl -s http://localhost:19999/api/v1/surfaces/focused | jq -r '.id')

if [ "$UUID" != "null" ] && [ -n "$UUID" ]; then
  curl -s -X POST "http://localhost:19999/api/v1/surfaces/$UUID/actions" \
    -H "Content-Type: application/json" \
    -d "{\"action\": \"text:$COMMAND\\n\"}"
else
  echo "No focused Ghostty surface found"
  exit 1
fi
```

Usage:
```bash
./run-in-ghostty.sh "git status"
```

---

### Create a New Split and Run a Command

```bash
#!/bin/bash
# split-and-run.sh - Create a split and run a command in it

COMMAND="$1"
DIRECTION="${2:-right}"

# Get the current focused surface
UUID=$(curl -s http://localhost:19999/api/v1/surfaces/focused | jq -r '.id')

# Create a new split
curl -s -X POST "http://localhost:19999/api/v1/surfaces/$UUID/actions" \
  -d "{\"action\": \"new_split:$DIRECTION\"}"

# Wait for the new split to be created and focused
sleep 0.5

# Get the new focused surface (the new split)
NEW_UUID=$(curl -s http://localhost:19999/api/v1/surfaces/focused | jq -r '.id')

# Run the command
curl -s -X POST "http://localhost:19999/api/v1/surfaces/$NEW_UUID/actions" \
  -d "{\"action\": \"text:$COMMAND\\n\"}"
```

---

### Monitor Terminal Output

```bash
#!/bin/bash
# watch-terminal.sh - Poll terminal screen contents

UUID="$1"
INTERVAL="${2:-1}"

while true; do
  clear
  echo "=== Terminal $UUID ==="
  curl -s "http://localhost:19999/api/v1/surfaces/$UUID/screen" | jq -r '.contents'
  sleep "$INTERVAL"
done
```

---

### List All Surfaces with Details

```bash
#!/bin/bash
# list-surfaces.sh - Pretty-print all surfaces

curl -s http://localhost:19999/api/v1/surfaces | jq -r '
  .surfaces[] |
  "\(.id)\t\(.title)\t\(.columns)x\(.rows)\t\(if .focused then "FOCUSED" else "" end)"
' | column -t -s $'\t'
```

---

### Editor Integration (Neovim Example)

```lua
-- ghostty.lua - Neovim plugin for Ghostty integration

local M = {}

local function api_call(method, path, body)
  local cmd = string.format("curl -s -X %s http://localhost:19999%s", method, path)
  if body then
    cmd = cmd .. string.format(" -H 'Content-Type: application/json' -d '%s'", body)
  end
  local handle = io.popen(cmd)
  local result = handle:read("*a")
  handle:close()
  return vim.json.decode(result)
end

function M.get_focused_surface()
  return api_call("GET", "/api/v1/surfaces/focused")
end

function M.send_text(text)
  local surface = M.get_focused_surface()
  if surface and surface.id then
    -- Escape special characters for JSON
    text = text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\"", "\\\"")
    api_call("POST", "/api/v1/surfaces/" .. surface.id .. "/actions",
      string.format('{"action": "text:%s"}', text))
  end
end

function M.run_command(cmd)
  M.send_text(cmd .. "\\n")
end

function M.new_split(direction)
  local surface = M.get_focused_surface()
  if surface and surface.id then
    api_call("POST", "/api/v1/surfaces/" .. surface.id .. "/actions",
      string.format('{"action": "new_split:%s"}', direction or "right"))
  end
end

-- Example keymaps
vim.keymap.set("n", "<leader>tr", function()
  M.run_command("!!")  -- Re-run last command
end, { desc = "Re-run last terminal command" })

vim.keymap.set("n", "<leader>ts", function()
  M.new_split("right")
end, { desc = "New Ghostty split" })

return M
```

---

### Python Client Library

```python
#!/usr/bin/env python3
"""ghostty.py - Python client for Ghostty REST API"""

import json
import urllib.request
from typing import Optional, List, Dict, Any

class GhosttyClient:
    def __init__(self, host: str = "localhost", port: int = 19999):
        self.base_url = f"http://{host}:{port}"

    def _request(self, method: str, path: str, body: Optional[dict] = None) -> dict:
        url = f"{self.base_url}{path}"
        data = json.dumps(body).encode() if body else None
        headers = {"Content-Type": "application/json"} if body else {}

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())

    def get_surfaces(self) -> List[Dict[str, Any]]:
        """List all terminal surfaces."""
        return self._request("GET", "/api/v1/surfaces")["surfaces"]

    def get_focused_surface(self) -> Optional[Dict[str, Any]]:
        """Get the currently focused surface."""
        try:
            return self._request("GET", "/api/v1/surfaces/focused")
        except urllib.error.HTTPError:
            return None

    def get_surface(self, uuid: str) -> Optional[Dict[str, Any]]:
        """Get a specific surface by UUID."""
        try:
            return self._request("GET", f"/api/v1/surfaces/{uuid}")
        except urllib.error.HTTPError:
            return None

    def get_screen_contents(self, uuid: str) -> str:
        """Get the screen contents of a surface."""
        return self._request("GET", f"/api/v1/surfaces/{uuid}/screen")["contents"]

    def execute_action(self, uuid: str, action: str) -> bool:
        """Execute an action on a surface."""
        result = self._request("POST", f"/api/v1/surfaces/{uuid}/actions",
                               {"action": action})
        return result.get("success", False)

    def send_text(self, uuid: str, text: str) -> bool:
        """Send text to a surface."""
        # Escape for Zig string literal format
        escaped = text.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
        return self.execute_action(uuid, f"text:{escaped}")

    def run_command(self, uuid: str, command: str) -> bool:
        """Run a command in a surface (sends text + Enter)."""
        return self.send_text(uuid, command + "\n")

    def new_split(self, uuid: str, direction: str = "auto") -> bool:
        """Create a new split."""
        return self.execute_action(uuid, f"new_split:{direction}")

    def new_tab(self, uuid: str) -> bool:
        """Create a new tab."""
        return self.execute_action(uuid, "new_tab")


# Example usage
if __name__ == "__main__":
    client = GhosttyClient()

    # List all surfaces
    for surface in client.get_surfaces():
        status = "FOCUSED" if surface["focused"] else ""
        print(f"{surface['id'][:8]}  {surface['title']:20}  {status}")

    # Run a command in the focused surface
    focused = client.get_focused_surface()
    if focused:
        client.run_command(focused["id"], "echo 'Hello from Python!'")
```

---

## Error Handling

### HTTP Status Codes

| Status | Meaning |
|--------|---------|
| 200 | Success |
| 400 | Bad Request (invalid UUID format, missing body, invalid JSON) |
| 404 | Not Found (invalid endpoint, surface not found) |
| 405 | Method Not Allowed (wrong HTTP method for endpoint) |
| 500 | Internal Server Error |

### Error Response Format

```json
{
  "error": "Human-readable error message"
}
```

### Common Errors

**Invalid UUID:**
```json
{
  "error": "Invalid UUID format"
}
```

**Surface not found:**
```json
{
  "error": "Surface not found: 550e8400-e29b-41d4-a716-446655440000"
}
```

**No focused surface:**
```json
{
  "error": "No focused surface"
}
```

**Action failed:**
```json
{
  "success": false,
  "action": "invalid_action",
  "error": "Action failed or not recognized"
}
```

---

## Troubleshooting

### API Not Responding

1. Check that Ghostty is running
2. Verify the API is enabled: `macos-api-server = true` in config
3. Check the port: `curl http://localhost:19999/`
4. Try the configured port if non-default

### Actions Not Working

1. Verify the surface UUID is valid: `GET /api/v1/surfaces`
2. Check action syntax matches exactly (case-sensitive)
3. Some actions are platform-specific (macOS vs Linux)
4. Check Ghostty logs for error messages

### Connection Refused

The API only binds to localhost. Ensure you're connecting from the same machine:
```bash
curl http://127.0.0.1:19999/
```
