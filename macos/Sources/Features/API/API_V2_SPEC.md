# Ghostty REST API v2 Specification

This document specifies the v2 REST API for Ghostty, designed to expose all App Intent functionality via HTTP endpoints.

## Table of Contents

- [Overview](#overview)
- [Design Philosophy](#design-philosophy)
- [Configuration](#configuration)
- [Authentication & Security](#authentication--security)
- [API Endpoints](#api-endpoints)
  - [Discovery](#discovery)
  - [Terminal Management](#terminal-management)
  - [Terminal Input](#terminal-input)
  - [Terminal Details](#terminal-details)
  - [Quick Terminal](#quick-terminal)
  - [Commands](#commands)
- [Data Types](#data-types)
- [Error Handling](#error-handling)
- [Migration from v1](#migration-from-v1)
- [Implementation Notes](#implementation-notes)

---

## Overview

The v2 API provides HTTP-based control over Ghostty terminals, exposing the same capabilities available through macOS Shortcuts/App Intents. This enables:

- Creating terminals with specific configurations (working directory, command, environment)
- Sending text input and simulating keyboard/mouse events
- Reading terminal contents and metadata
- Managing terminal focus and lifecycle
- Controlling the quick terminal

### Base URL

```
http://localhost:19999/api/v2
```

### Quickstart

```bash
# Create a new terminal tab with a specific working directory
curl -X POST http://localhost:19999/api/v2/terminals \
  -H "Content-Type: application/json" \
  -d '{
    "location": "tab",
    "working_directory": "/Users/demo/projects",
    "command": "npm run dev"
  }'

# Send text to a terminal
curl -X POST http://localhost:19999/api/v2/terminals/{id}/input \
  -H "Content-Type: application/json" \
  -d '{"text": "git status", "enter": true}'

# Get terminal screen contents
curl http://localhost:19999/api/v2/terminals/{id}/screen
```

---

## Design Philosophy

### Intent-Driven Design

The v1 API was surface-centric with limited action support. The v2 API is **intent-driven**, mapping directly to macOS App Intents:

| App Intent | HTTP Endpoint |
|------------|---------------|
| `NewTerminalIntent` | `POST /terminals` |
| `CloseTerminalIntent` | `DELETE /terminals/{id}` |
| `FocusTerminalIntent` | `POST /terminals/{id}/focus` |
| `InputTextIntent` | `POST /terminals/{id}/input` |
| `KeybindIntent` | `POST /terminals/{id}/action` |
| `KeyEventIntent` | `POST /terminals/{id}/key` |
| `MouseButtonIntent` | `POST /terminals/{id}/mouse/button` |
| `MousePosIntent` | `POST /terminals/{id}/mouse/position` |
| `MouseScrollIntent` | `POST /terminals/{id}/mouse/scroll` |
| `GetTerminalDetailsIntent` | `GET /terminals/{id}/details/{type}` |
| `QuickTerminalIntent` | `POST /quick-terminal` |
| `CommandPaletteIntent` | `POST /terminals/{id}/action` |

### RESTful Resource Naming

- **Terminals** (not "surfaces") - clearer terminology for external consumers
- Hierarchical paths for related operations (`/terminals/{id}/mouse/button`)
- HTTP verbs match intent (`DELETE` for close, `POST` for actions)

### Simplified Input

v1 required Zig escape syntax (`text:hello\\n`). v2 uses raw text in JSON, making it easier for clients in any language.

---

## Configuration

The API server is controlled by configuration options in `~/.config/ghostty/config`:

```ini
# Enable the API server (default: true)
macos-api-server = true

# Set the port (default: 19999)
macos-api-server-port = 19999
```

---

## Authentication & Security

- The server binds to `127.0.0.1` (localhost) only
- No authentication required - any local process can access the API
- The API cannot be accessed from remote machines
- Consider the security implications of exposing terminal control to local processes

---

## API Endpoints

### Discovery

#### `GET /api/v2/`

Returns API version and available endpoints.

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

### Terminal Management

#### `GET /api/v2/terminals`

List all terminals.

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

**Terminal Object Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID identifying the terminal |
| `title` | string | Terminal title (shell or running command) |
| `working_directory` | string? | Current working directory |
| `kind` | string | `"normal"` or `"quick"` |
| `focused` | boolean | Whether this terminal has keyboard focus |
| `columns` | integer | Terminal width in columns |
| `rows` | integer | Terminal height in rows |
| `cell_width` | integer | Cell width in pixels |
| `cell_height` | integer | Cell height in pixels |

---

#### `GET /api/v2/terminals/focused`

Get the currently focused terminal.

**Response:** Terminal object (see above)

**Error Response (no focused terminal):**
```json
{
  "error": "no_focused_terminal",
  "message": "No terminal is currently focused"
}
```

---

#### `GET /api/v2/terminals/{id}`

Get a specific terminal by UUID.

**Response:** Terminal object

---

#### `POST /api/v2/terminals`

Create a new terminal window, tab, or split.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `location` | string | No | Where to create: `"window"` (default), `"tab"`, `"split:left"`, `"split:right"`, `"split:up"`, `"split:down"` |
| `command` | string | No | Command to execute after shell initialization |
| `working_directory` | string | No | Initial working directory path |
| `env` | object | No | Environment variables as key-value pairs |
| `parent` | string | No | UUID of parent terminal (for tabs/splits) |

**Example - New tab with command:**
```json
{
  "location": "tab",
  "working_directory": "/Users/demo/projects/myapp",
  "command": "npm run dev",
  "env": {
    "NODE_ENV": "development",
    "DEBUG": "app:*"
  }
}
```

**Example - Split from existing terminal:**
```json
{
  "location": "split:right",
  "parent": "550e8400-e29b-41d4-a716-446655440000",
  "working_directory": "/Users/demo/projects/myapp"
}
```

**Response:**
```json
{
  "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "title": "zsh",
  "working_directory": "/Users/demo/projects/myapp",
  "kind": "normal",
  "focused": true,
  "columns": 80,
  "rows": 24,
  "cell_width": 10,
  "cell_height": 20
}
```

**Notes:**
- The `command` is executed via `initialInput` after shell login scripts run, ensuring PATH and other environment setup is complete
- The command appends `; exit\n`, so the shell exits when the command completes
- For splits, if no `parent` is specified, uses the currently focused terminal
- Returns the newly created terminal object

---

#### `DELETE /api/v2/terminals/{id}`

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

#### `POST /api/v2/terminals/{id}/focus`

Focus a specific terminal, bringing its window to the front.

**Request Body:** None required (empty object `{}`)

**Response:**
```json
{
  "success": true
}
```

---

### Terminal Input

#### `POST /api/v2/terminals/{id}/input`

Send text input to a terminal (like pasting).

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | string | Yes | Text to input |
| `enter` | boolean | No | Send Enter key after input |

**Example:**
```json
{
  "text": "echo 'Hello, World!'",
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
- Use `enter: true` to send the Enter key after input
- For control characters or key events, use the `/key` endpoint instead

---

#### `POST /api/v2/terminals/{id}/output`

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

#### `POST /api/v2/terminals/{id}/statusbar`

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

#### `POST /api/v2/terminals/{id}/action`

Execute a keybind action on a terminal.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | Yes | The keybind action to invoke |

**Example:**
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

**Available Actions:**

See the full action reference in API_GUIDE.md. Common actions include:

- `copy_to_clipboard`, `paste_from_clipboard`
- `new_window`, `new_tab`, `new_split:{direction}`
- `close_surface`, `close_tab`, `close_window`
- `goto_split:{direction}`, `goto_tab:{n}`
- `scroll_page_up`, `scroll_page_down`, `scroll_to_top`, `scroll_to_bottom`
- `toggle_fullscreen`, `toggle_split_zoom`
- `clear_screen`, `reset`

---

#### `POST /api/v2/terminals/{id}/key`

Send a keyboard event to simulate key presses.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | Yes | Key name (see Key Names below) |
| `mods` | array | No | Modifier keys: `"shift"`, `"control"`, `"option"`, `"command"` |
| `action` | string | No | `"press"` (default) or `"release"` |

**Example - Send Ctrl+C:**
```json
{
  "key": "c",
  "mods": ["control"],
  "action": "press"
}
```

**Example - Send Enter:**
```json
{
  "key": "enter"
}
```

**Response:**
```json
{
  "success": true
}
```

**Key Names:**

Common keys: `a`-`z`, `0`-`9`, `enter`, `escape`, `tab`, `space`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `home`, `end`, `page_up`, `page_down`, `f1`-`f12`

---

#### `POST /api/v2/terminals/{id}/mouse/button`

Send a mouse button event.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `button` | string | Yes | `"left"`, `"right"`, `"middle"` |
| `action` | string | No | `"press"` (default) or `"release"` |
| `mods` | array | No | Modifier keys |

**Example:**
```json
{
  "button": "left",
  "action": "press",
  "mods": ["control"]
}
```

**Response:**
```json
{
  "success": true
}
```

---

#### `POST /api/v2/terminals/{id}/mouse/position`

Send a mouse position/movement event.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `x` | number | Yes | Horizontal position |
| `y` | number | Yes | Vertical position |
| `mods` | array | No | Modifier keys |

**Example:**
```json
{
  "x": 150.0,
  "y": 200.0
}
```

**Response:**
```json
{
  "success": true
}
```

**Notes:**
- Coordinates are passed through to the Ghostty App Intent used by Shortcuts; use the same coordinate space and units as Shortcuts

---

#### `POST /api/v2/terminals/{id}/mouse/scroll`

Send a mouse scroll event.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `x` | number | No | Horizontal scroll delta (default: 0) |
| `y` | number | No | Vertical scroll delta (default: 0) |
| `precision` | boolean | No | High-precision scrolling (trackpad) |
| `momentum` | string | No | Momentum phase for inertial scrolling |

**Momentum Values:** `"none"`, `"began"`, `"changed"`, `"ended"`, `"cancelled"`, `"stationary"`

**Example - Scroll down:**
```json
{
  "y": -3.0,
  "precision": false
}
```

**Response:**
```json
{
  "success": true
}
```

**Notes:**
- Scroll deltas and momentum values are passed through to the Ghostty App Intent used by Shortcuts

---

### Terminal Details

#### `GET /api/v2/terminals/{id}/screen`

Get the full screen contents including scrollback.

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "contents": "user@host:~/projects$ ls\nfile1.txt  file2.txt  src/\nuser@host:~/projects$ "
}
```

**Notes:**
- This is equivalent to `GET /api/v2/terminals/{id}/details/contents`, but keeps the v1 response shape for compatibility

---

#### `GET /api/v2/terminals/{id}/details/{type}`

Get specific details about a terminal.

**Path Parameters:**

| Parameter | Description |
|-----------|-------------|
| `type` | One of: `title`, `working_directory`, `contents`, `selection`, `visible` |

**Detail Types:**

| Type | Description |
|------|-------------|
| `title` | Terminal title |
| `working_directory` | Current working directory |
| `contents` | Full screen contents including scrollback |
| `selection` | Currently selected text |
| `visible` | Only the visible portion of the screen |

**Response:**
```json
{
  "type": "selection",
  "value": "selected text here"
}
```

**Notes:**
- `contents` matches the `/screen` endpoint contents; `visible` returns only the visible viewport

---

### Quick Terminal

#### `POST /api/v2/quick-terminal`

Open the quick/dropdown terminal. If already open, does nothing.

**Request Body:** None required (empty object `{}`)

**Response:**
```json
{
  "terminals": [
    {
      "id": "...",
      "title": "zsh",
      "kind": "quick",
      ...
    }
  ]
}
```

---

### Commands

#### `GET /api/v2/commands`

List all available command palette commands.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `terminal` | string | UUID of terminal to get context-specific commands |

**Response:**
```json
{
  "commands": [
    {
      "action_key": "new_window",
      "action": "new_window",
      "title": "New Window",
      "description": "Open a new terminal window"
    },
    {
      "action_key": "new_tab",
      "action": "new_tab",
      "title": "New Tab",
      "description": "Open a new tab"
    }
  ]
}
```

---

## Data Types

### JSON Field Naming

For compatibility with v1, JSON fields use `snake_case` for multi-word keys (for example: `working_directory`, `cell_width`, `action_key`).

### Terminal Location

```typescript
type TerminalLocation =
  | "window"      // New window (default)
  | "tab"         // New tab in existing/parent window
  | "split:left"  // Split left of parent
  | "split:right" // Split right of parent
  | "split:up"    // Split above parent
  | "split:down"  // Split below parent
```

### Terminal Kind

```typescript
type TerminalKind = "normal" | "quick"
```

### Modifier Keys

```typescript
type ModifierKey = "shift" | "control" | "option" | "command"
```

### Mouse Button

```typescript
type MouseButton = "left" | "right" | "middle"
```

### Key Action

```typescript
type KeyAction = "press" | "release"
```

### Scroll Momentum

```typescript
type ScrollMomentum =
  | "none"
  | "began"
  | "changed"
  | "ended"
  | "cancelled"
  | "stationary"
```

---

## Error Handling

### HTTP Status Codes

| Status | Meaning |
|--------|---------|
| 200 | Success |
| 400 | Bad Request (invalid JSON, missing required fields) |
| 404 | Not Found (invalid endpoint, terminal not found) |
| 405 | Method Not Allowed |
| 500 | Internal Server Error |

### Error Response Format

```json
{
  "error": "error_code",
  "message": "Human-readable error message"
}
```

### Error Codes

| Code | Description |
|------|-------------|
| `invalid_json` | Request body is not valid JSON |
| `missing_field` | Required field is missing |
| `invalid_uuid` | UUID format is invalid |
| `terminal_not_found` | Terminal with given UUID doesn't exist |
| `no_focused_terminal` | No terminal is currently focused |
| `invalid_location` | Invalid terminal location value |
| `invalid_action` | Unknown keybind action |
| `action_failed` | Action was recognized but failed to execute |
| `permission_denied` | App intent permission was denied (only when permission checks are enabled) |

---

## Migration from v1

### Endpoint Changes

| v1 Endpoint | v2 Endpoint |
|-------------|-------------|
| `GET /api/v1/surfaces` | `GET /api/v2/terminals` |
| `GET /api/v1/surfaces/focused` | `GET /api/v2/terminals/focused` |
| `GET /api/v1/surfaces/{uuid}` | `GET /api/v2/terminals/{id}` |
| `GET /api/v1/surfaces/{uuid}/screen` | `GET /api/v2/terminals/{id}/screen` |
| `GET /api/v1/surfaces/{uuid}/commands` | `GET /api/v2/commands?terminal={id}` |
| `POST /api/v1/surfaces/{uuid}/actions` | `POST /api/v2/terminals/{id}/action` |

### New in v2

- `POST /api/v2/terminals` - Create terminals with configuration
- `DELETE /api/v2/terminals/{id}` - Close terminals
- `POST /api/v2/terminals/{id}/focus` - Focus terminals
- `POST /api/v2/terminals/{id}/input` - Text input (replaces `text:` action)
- `POST /api/v2/terminals/{id}/output` - Terminal output injection (OSC/CSI)
- `POST /api/v2/terminals/{id}/statusbar` - Programmable status bar
- `POST /api/v2/terminals/{id}/key` - Key events
- `POST /api/v2/terminals/{id}/mouse/*` - Mouse events
- `GET /api/v2/terminals/{id}/details/{type}` - Granular detail access
- `POST /api/v2/quick-terminal` - Quick terminal control

### Breaking Changes

1. **Resource naming**: `surfaces` → `terminals`
2. **Text input**: The `text:VALUE` action syntax is replaced by `POST /terminals/{id}/input` with raw text
3. **Response field**: `id` instead of `uuid` in some contexts

### Compatibility

The v1 API will remain available at `/api/v1/` for backward compatibility. New integrations should use v2.

JSON field naming matches v1 (`snake_case`) to keep payloads consistent across versions.

---

## Implementation Notes

### Swift Intent Mapping

The v2 API maps directly to existing App Intents in `macos/Sources/Features/App Intents/`:

| File | Intent | v2 Endpoint |
|------|--------|-------------|
| `NewTerminalIntent.swift` | `NewTerminalIntent` | `POST /terminals` |
| `CloseTerminalIntent.swift` | `CloseTerminalIntent` | `DELETE /terminals/{id}` |
| `FocusTerminalIntent.swift` | `FocusTerminalIntent` | `POST /terminals/{id}/focus` |
| `InputIntent.swift` | `InputTextIntent` | `POST /terminals/{id}/input` |
| `InputIntent.swift` | `KeyEventIntent` | `POST /terminals/{id}/key` |
| `InputIntent.swift` | `MouseButtonIntent` | `POST /terminals/{id}/mouse/button` |
| `InputIntent.swift` | `MousePosIntent` | `POST /terminals/{id}/mouse/position` |
| `InputIntent.swift` | `MouseScrollIntent` | `POST /terminals/{id}/mouse/scroll` |
| `KeybindIntent.swift` | `KeybindIntent` | `POST /terminals/{id}/action` |
| `GetTerminalDetailsIntent.swift` | `GetTerminalDetailsIntent` | `GET /terminals/{id}/details/{type}` |
| `QuickTerminalIntent.swift` | `QuickTerminalIntent` | `POST /quick-terminal` |
| `CommandPaletteIntent.swift` | `CommandPaletteIntent` | `POST /terminals/{id}/action` |

### SurfaceConfiguration

When creating terminals, the API should construct a `Ghostty.SurfaceConfiguration`:

```swift
struct SurfaceConfiguration {
    var fontSize: Float32?
    var workingDirectory: String?
    var command: String?
    var environmentVariables: [String: String] = [:]
    var initialInput: String?
    var waitAfterCommand: Bool = false
}
```

**Note:** The `command` parameter should be converted to `initialInput` with `; exit\n` appended, matching `NewTerminalIntent` behavior:

```swift
if let command = requestBody.command {
    config.initialInput = "\(command); exit\n"
}
```

This means the shell exits when the command completes.

### TerminalEntity Properties

The `TerminalEntity` in `Entities/TerminalEntity.swift` exposes:

- `id: UUID`
- `title: String`
- `workingDirectory: String?`
- `kind: Kind` (`.normal` or `.quick`)

Additional properties like `columns`, `rows`, `cell_width`, `cell_height` come from the underlying `SurfaceView`.

### Router Implementation

The core router in `macos/Sources/Features/API/APICoreRouter.swift` should handle v2 routes. HTTP requests are adapted via `APIHTTPAdapter.swift`. Consider a structure like:

```swift
func route(_ request: APIRequest) -> APIResponse {
    switch (request.method, request.path) {
    case ("GET", "/terminals"):
        return handleListTerminals()
    case ("POST", "/terminals"):
        return handleCreateTerminal(request)
    case ("DELETE", let path) where path.hasPrefix("/terminals/"):
        return handleDeleteTerminal(request)
    // ... etc
    }
}
```

### Permission Handling

All App Intents call `requestIntentPermission()`. The API should either:
1. Bypass this check (since API access implies local trust)
2. Have a separate permission model for API access
3. Respect the same permission system

Recommendation: Bypass for API since localhost binding already implies trust.

If permission checks are bypassed, `permission_denied` will not be returned. If the same permission system is respected, clients should be prepared to handle it.

---

## Examples

### Create a Development Environment

```bash
#!/bin/bash
# dev-env.sh - Set up a development environment with multiple panes

API="http://localhost:19999/api/v2"
PROJECT="/Users/demo/projects/myapp"

# Create main window with editor
MAIN=$(curl -s -X POST "$API/terminals" \
  -H "Content-Type: application/json" \
  -d "{
    \"location\": \"window\",
    \"working_directory\": \"$PROJECT\",
    \"command\": \"nvim .\"
  }" | jq -r '.id')

sleep 0.5

# Split right for server
curl -s -X POST "$API/terminals" \
  -H "Content-Type: application/json" \
  -d "{
    \"location\": \"split:right\",
    \"parent\": \"$MAIN\",
    \"working_directory\": \"$PROJECT\",
    \"command\": \"npm run dev\"
  }"

sleep 0.5

# Split down for git/misc
curl -s -X POST "$API/terminals" \
  -H "Content-Type: application/json" \
  -d "{
    \"location\": \"split:down\",
    \"parent\": \"$MAIN\",
    \"working_directory\": \"$PROJECT\"
  }"
```

### Send Ctrl+C to Stop a Process

```bash
curl -X POST "http://localhost:19999/api/v2/terminals/$UUID/key" \
  -H "Content-Type: application/json" \
  -d '{"key": "c", "mods": ["control"]}'
```

### Get Selected Text for Processing

```bash
SELECTION=$(curl -s "http://localhost:19999/api/v2/terminals/$UUID/details/selection" \
  | jq -r '.value')

echo "Selected: $SELECTION"
```

### Toggle Quick Terminal from Script

```bash
curl -X POST "http://localhost:19999/api/v2/quick-terminal" \
  -H "Content-Type: application/json" \
  -d '{}'
```
