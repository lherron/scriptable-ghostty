# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

# PROJECT ID:  The project id for this project is "ghostty" and should be used in wrkq requests.

## Commands

- **Build (macOS app):** `just build`
- **Install (macOS app):** `just install`
- **Build Zig core:** `just build-zig`
- **Test (Zig):** `zig build test`
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt .`
- **Formatting (other)**: `prettier -w .`

## Directory Structure

- Shared Zig core: `src/`
- C API: `include`
- macOS app: `macos/`
- GTK (Linux and FreeBSD) app: `src/apprt/gtk`

## libghostty-vt

- Build: `zig build lib-vt`
- Build Wasm Module: `zig build lib-vt -Dtarget=wasm32-freestanding`
- Test: `zig build test-lib-vt`
- Test filter: `zig build test-lib-vt -Dtest-filter=<test name>`
- When working on libghostty-vt, do not build the full app.
- For C only changes, don't run the Zig tests. Build all the examples.

## macOS App

- Do not use `xcodebuild`
- Use `just build` to build the macOS app and any shared Zig code
- Use `just install` to install the macOS app (do not use `zig build install`)
- Use `zig build run` to build and run the macOS app
- Run Xcode tests using `zig build test`

## API & ghostmux quick hits

- **HTTP API (macOS only):** `macos/Sources/Features/API/` (APIServer + core router + handlers).
- **UDS socket:** `~/Library/Application Support/Ghostty/api.sock` (per-user).
- **UDS framing:** 4-byte big-endian length prefix + JSON payload.
- **UDS test (Python):**
  ```bash
  python3 - <<'PY'
  import json, os, socket, struct
  sock_path = os.path.expanduser('~/Library/Application Support/Ghostty/api.sock')
  req = {"version":"v2","method":"GET","path":"/terminals"}
  payload = json.dumps(req).encode('utf-8')
  frame = struct.pack('>I', len(payload)) + payload
  with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
      s.connect(sock_path)
      s.sendall(frame)
      hdr = s.recv(4)
      length = struct.unpack('>I', hdr)[0]
      data = b''
      while len(data) < length:
          data += s.recv(length - len(data))
  print(data.decode('utf-8'))
  PY
  ```
- **ghostmux CLI (UDS-only):**
  - Source: `macos/Tools/ghostmux/main.swift`
  - Build: `just ghostmux`
  - Install: `just install-ghostmux` (also bundles into app)
  - Target usage: `ghostmux send-keys -t <target> ...` (requires `-t`)
- **Key events:** ghostmux uses `/api/v2/terminals/{id}/key` with `text` + `unshifted_codepoint` for proper typing (no paste highlight).

## Screenshots (ScriptableGhostty on this laptop)

Use `osascript` to query the window bounds for the ScriptableGhostty process, then
capture that rectangle with `screencapture`.

When asked to test manually, always run `ghostmux capture-pane` to capture the
screen buffer, then capture a screenshot and review it (open/attach it) before
reporting results.

When restarting ScriptableGhostty, use `just restart` or `just debug`, and ensure
the existing app is terminated before starting a new instance.

```bash
# Activate ScriptableGhostty (optional)
osascript -e 'tell application id "com.lherron.scriptableghostty" to activate'

# Get window bounds (top-left + size)
osascript -e 'tell application "System Events" to tell (first process whose bundle identifier is "com.lherron.scriptableghostty") to get position of window 1'
osascript -e 'tell application "System Events" to tell (first process whose bundle identifier is "com.lherron.scriptableghostty") to get size of window 1'

# Example capture (replace coords with output from above)
screencapture -x -R 1129,161,574,324 /tmp/scriptableghostty.png
```

If needed, capture the full screen instead:
```bash
screencapture -x /tmp/screen.png
```
