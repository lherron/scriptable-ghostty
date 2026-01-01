# Ghostty macOS REST API

Ghostty provides a localhost REST API for programmatic control of terminal surfaces. The API allows external tools and scripts to query terminal state and execute actions.

## Overview

- **Protocols**: HTTP/1.1, Unix domain socket (UDS)
- **HTTP Base URL**: `http://127.0.0.1:<port>/api/v1`
- **Content-Type**: `application/json`
- **Binding**: Localhost only (`acceptLocalOnly = true`) for HTTP; per-user file permissions for UDS.

The API server uses Apple's Network framework (`NWListener`) for connection handling and routes requests through a transport-agnostic core router to the appropriate handlers. The UDS transport is documented in `UDS_SPEC.md`.

## Architecture

| File | Purpose |
|------|---------|
| `APIServer.swift` | TCP listener management, connection handling |
| `APIHTTPAdapter.swift` | HTTP <-> core request/response adaptation |
| `APICoreRouter.swift` | Transport-agnostic routing to handlers |
| `APICoreTypes.swift` | Core request/response models |
| `APIHandlers.swift` | Business logic for each endpoint |
| `APIModels.swift` | Request/response data structures |
| `HTTPParser.swift` | HTTP/1.1 parsing and response serialization |

## Endpoints

### API Information

#### `GET /api/v1`

Returns API version and list of available endpoints.

**Response:**
```json
{
  "version": "1",
  "endpoints": [
    "GET /api/v1/surfaces",
    "GET /api/v1/surfaces/focused",
    "GET /api/v1/surfaces/{uuid}",
    "GET /api/v1/surfaces/{uuid}/commands",
    "POST /api/v1/surfaces/{uuid}/actions"
  ]
}
```

---

### Surfaces

A "surface" represents a terminal view in Ghostty (a tab or split pane).

#### `GET /api/v1/surfaces`

Lists all terminal surfaces.

**Response:**
```json
{
  "surfaces": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "zsh",
      "working_directory": "/Users/user/projects",
      "focused": true,
      "columns": 120,
      "rows": 40,
      "cell_width": 9,
      "cell_height": 18
    }
  ]
}
```

#### `GET /api/v1/surfaces/focused`

Returns the currently focused surface.

**Response:** Same as individual surface (see below).

**Errors:**
- `404` - No focused surface exists

#### `GET /api/v1/surfaces/{uuid}`

Returns a specific surface by UUID.

**Path Parameters:**
- `uuid` - The surface UUID (e.g., `550e8400-e29b-41d4-a716-446655440000`)

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "zsh",
  "working_directory": "/Users/user/projects",
  "focused": true,
  "columns": 120,
  "rows": 40,
  "cell_width": 9,
  "cell_height": 18
}
```

**Errors:**
- `400` - Invalid UUID format
- `404` - Surface not found

---

### Commands

Commands are predefined actions with human-readable metadata, suitable for displaying in a command palette or UI. They map directly to Ghostty's keybind actions.

#### `GET /api/v1/surfaces/{uuid}/commands`

Lists available commands for a surface.

**Path Parameters:**
- `uuid` - The surface UUID

**Response:**
```json
{
  "commands": [
    {
      "action_key": "copy_to_clipboard",
      "action": "copy_to_clipboard:mixed",
      "title": "Copy to Clipboard",
      "description": "Copy the selected text to the clipboard in both plain and styled formats."
    }
  ]
}
```

**Fields:**
- `action_key` - The base action type (e.g., `copy_to_clipboard`, `new_split`)
- `action` - The full action string including parameters (e.g., `new_split:right`)
- `title` - Human-readable title for display
- `description` - Detailed description of what the command does

**Errors:**
- `400` - Invalid UUID format
- `404` - Surface not found
- `500` - Surface has no model / failed to get commands

**Note:** Some actions are filtered out on macOS as unsupported:
- `toggle_tab_overview` - Linux/GTK only
- `toggle_window_decorations` - Linux only
- `show_gtk_inspector` - GTK only

---

### Actions

Actions are the core operations that can be performed on a surface. They use Ghostty's keybind action syntax.

#### `POST /api/v1/surfaces/{uuid}/actions`

Executes an action on a surface.

**Path Parameters:**
- `uuid` - The surface UUID

**Request Body:**
```json
{
  "action": "copy_to_clipboard"
}
```

**Response (success):**
```json
{
  "success": true,
  "action": "copy_to_clipboard"
}
```

**Response (failure):**
```json
{
  "success": false,
  "action": "copy_to_clipboard",
  "error": "Action failed or not recognized"
}
```

**Errors:**
- `400` - Invalid UUID format / missing request body / invalid JSON
- `404` - Surface not found
- `500` - Surface has no model

---

## Action Reference

Actions use the same syntax as Ghostty's `keybind` configuration. Many actions accept parameters using a colon separator: `action_name:parameter`.

### Clipboard Actions

| Action | Description |
|--------|-------------|
| `copy_to_clipboard` | Copy selection (default: mixed format) |
| `copy_to_clipboard:plain` | Copy as plain text |
| `copy_to_clipboard:vt` | Copy with ANSI escape sequences |
| `copy_to_clipboard:html` | Copy as HTML |
| `copy_to_clipboard:mixed` | Copy in both plain and styled formats |
| `paste_from_clipboard` | Paste from system clipboard |
| `paste_from_selection` | Paste from selection clipboard |
| `copy_url_to_clipboard` | Copy URL under cursor |
| `copy_title_to_clipboard` | Copy terminal title |

### Font Actions

| Action | Description |
|--------|-------------|
| `increase_font_size:N` | Increase font size by N points (e.g., `increase_font_size:1`) |
| `decrease_font_size:N` | Decrease font size by N points |
| `reset_font_size` | Reset to configured default |
| `set_font_size:N` | Set font size to N points (e.g., `set_font_size:14.5`) |

### Navigation & Scrolling

| Action | Description |
|--------|-------------|
| `scroll_to_top` | Scroll to top of scrollback |
| `scroll_to_bottom` | Scroll to bottom |
| `scroll_to_selection` | Scroll to selected text |
| `scroll_page_up` | Scroll up one page |
| `scroll_page_down` | Scroll down one page |
| `scroll_page_fractional:N` | Scroll by fraction of page (e.g., `0.5` for half page, `-1.5` for 1.5 pages up) |
| `scroll_page_lines:N` | Scroll by N lines (negative for up) |
| `scroll_to_row:N` | Scroll to absolute row N |
| `jump_to_prompt:N` | Jump N prompts (requires shell integration) |

### Search

| Action | Description |
|--------|-------------|
| `start_search` | Open search UI |
| `end_search` | Close search |
| `search:TEXT` | Search for specific text |
| `navigate_search:next` | Go to next result |
| `navigate_search:previous` | Go to previous result |

### Selection

| Action | Description |
|--------|-------------|
| `select_all` | Select all text |
| `adjust_selection:DIRECTION` | Adjust selection (`left`, `right`, `up`, `down`, `page_up`, `page_down`, `home`, `end`, `beginning_of_line`, `end_of_line`) |

### Window & Tab Management

| Action | Description |
|--------|-------------|
| `new_window` | Open new window |
| `new_tab` | Open new tab |
| `close_surface` | Close current surface (tab/split) |
| `close_tab` | Close current tab |
| `close_tab:this` | Close current tab (explicit) |
| `close_tab:other` | Close all other tabs |
| `close_tab:right` | Close tabs to the right |
| `close_window` | Close current window |
| `previous_tab` | Go to previous tab |
| `next_tab` | Go to next tab |
| `last_tab` | Go to last tab |
| `goto_tab:N` | Go to tab N (1-indexed) |
| `move_tab:N` | Move tab by N positions (negative for left) |
| `toggle_fullscreen` | Toggle fullscreen |
| `toggle_maximize` | Toggle maximize (Linux only) |
| `toggle_window_float_on_top` | Toggle always-on-top (macOS only) |
| `reset_window_size` | Reset to default size |

### Split Management

| Action | Description |
|--------|-------------|
| `new_split:DIRECTION` | Create split (`left`, `right`, `up`, `down`, `auto`) |
| `goto_split:DIRECTION` | Focus split (`left`, `right`, `up`, `down`, `previous`, `next`) |
| `toggle_split_zoom` | Zoom/unzoom current split |
| `resize_split:DIRECTION,AMOUNT` | Resize split (e.g., `resize_split:up,10`) |
| `equalize_splits` | Make all splits equal size |

### Terminal Control

| Action | Description |
|--------|-------------|
| `reset` | Reset terminal state |
| `clear_screen` | Clear screen and scrollback |
| `text:STRING` | Send text to terminal (Zig string syntax) |
| `csi:SEQUENCE` | Send CSI sequence (e.g., `csi:0m` to reset styles) |
| `esc:SEQUENCE` | Send ESC sequence |

### File Operations

| Action | Description |
|--------|-------------|
| `write_screen_file:ACTION` | Write screen to temp file (`copy`, `paste`, `open`) |
| `write_screen_file:ACTION,FORMAT` | With format (`plain`, `vt`, `html`) |
| `write_scrollback_file:ACTION` | Write scrollback to temp file |
| `write_selection_file:ACTION` | Write selection to temp file |

### Application Control

| Action | Description |
|--------|-------------|
| `open_config` | Open config file in editor |
| `reload_config` | Reload configuration |
| `toggle_command_palette` | Toggle command palette |
| `toggle_quick_terminal` | Toggle quick/quake terminal |
| `toggle_visibility` | Show/hide all windows (macOS) |
| `toggle_secure_input` | Toggle secure input mode (macOS) |
| `toggle_mouse_reporting` | Toggle mouse event reporting |
| `inspector:toggle` | Toggle terminal inspector |
| `inspector:show` | Show inspector |
| `inspector:hide` | Hide inspector |
| `check_for_updates` | Check for updates (macOS) |
| `undo` | Undo last action (macOS) |
| `redo` | Redo last action (macOS) |
| `quit` | Quit application |

### Special Actions

| Action | Description |
|--------|-------------|
| `ignore` | Ignore this key combination |
| `unbind` | Remove a keybinding |
| `prompt_surface_title` | Prompt to change terminal title |
| `crash:THREAD` | Crash for testing (`main`, `io`, `render`) |

---

## Data Models

### SurfaceModel

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID of the surface |
| `title` | string | Terminal title |
| `working_directory` | string? | Current working directory (if available) |
| `focused` | boolean | Whether this surface has focus |
| `columns` | integer? | Terminal width in columns |
| `rows` | integer? | Terminal height in rows |
| `cell_width` | integer? | Cell width in pixels |
| `cell_height` | integer? | Cell height in pixels |

### CommandModel

| Field | Type | Description |
|-------|------|-------------|
| `action_key` | string | Internal action identifier |
| `action` | string | Action string to use in requests |
| `title` | string | Human-readable title |
| `description` | string | Description of what the command does |

---

## Error Responses

All errors return JSON with a consistent structure:

```json
{
  "error": "error_type",
  "message": "Human-readable description"
}
```

| Status Code | Error Type | Description |
|-------------|------------|-------------|
| 400 | `bad_request` | Invalid request (bad UUID, missing body, malformed JSON) |
| 404 | `not_found` | Resource not found (surface, endpoint) |
| 405 | `method_not_allowed` | HTTP method not supported for endpoint |
| 500 | `internal_error` | Server-side error |

### Method Not Allowed (405)

Includes an `Allow` header and allowed methods in the body:

```json
{
  "error": "method_not_allowed",
  "allowed": ["GET"]
}
```

---

## Usage Examples

### List all surfaces
```bash
curl http://127.0.0.1:5151/api/v1/surfaces
```

### Get focused surface
```bash
curl http://127.0.0.1:5151/api/v1/surfaces/focused
```

### Get specific surface
```bash
curl http://127.0.0.1:5151/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000
```

### List commands for a surface
```bash
curl http://127.0.0.1:5151/api/v1/surfaces/550e8400-e29b-41d4-a716-446655440000/commands
```

### Execute actions

Copy selection to clipboard:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "copy_to_clipboard"}'
```

Copy as HTML:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "copy_to_clipboard:html"}'
```

Create a split to the right:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "new_split:right"}'
```

Go to tab 3:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "goto_tab:3"}'
```

Increase font size by 2 points:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "increase_font_size:2"}'
```

Scroll down half a page:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "scroll_page_fractional:0.5"}'
```

Send text to terminal:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "text:ls -la\\n"}'
```

Resize split upward by 50 pixels:
```bash
curl -X POST http://127.0.0.1:5151/api/v1/surfaces/$UUID/actions \
  -H "Content-Type: application/json" \
  -d '{"action": "resize_split:up,50"}'
```

---

## Implementation Notes

- The server accepts connections only from localhost for security
- Maximum request size is 64KB
- Connections are closed after each response (`Connection: close`)
- All handler methods run on `@MainActor` for thread safety with Ghostty's UI
- JSON encoding uses snake_case for keys (`keyEncodingStrategy = .convertToSnakeCase`)
