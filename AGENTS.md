# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

# PROJECT ID: The project id for this project is "ghostty" and should be used in wrkq requests.

## Commands

- **Build (macOS app):** `just build`
- **Install (macOS app):** `just install`
- **Build Zig core:** `just build-zig`
- **Build without macOS app:** `zig build -Demit-macos-app=false`
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt .`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w .`
- **Zig toolchain:** 0.16.0 (`build.zig.zon` pins `minimum_zig_version`). Do not
  pin an older zig via `ZIG` in `.env.local`: zig 0.15.2 cannot link on
  macOS 26.5 / Xcode 26.

## libghostty-vt

- Build: `zig build -Demit-lib-vt`
- Build WASM: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
- Test: `zig build test-lib-vt -Dtest-filter=<filter>`
  - Prefer this when the change is in a libghostty-vt file
- All C enums in `include/ghostty/vt/` must have a `_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE`
  sentinel as the last entry to force int enum sizing (pre-C23 portability).

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- GTK (Linux and FreeBSD) app: `src/apprt/gtk`

## Upstream Safety

- The `upstream` remote is fetch-only. Never push branches, tags, or objects to
  `ghostty-org/ghostty`; all fork publication goes to `origin` only.

## macOS App

- Do not use `xcodebuild`
- Use `just build` to build the macOS app and any shared Zig code
- Use `just install` to install the macOS app (do not use `zig build install`)
- Use `zig build run` to build and run the macOS app
- Run Xcode tests using `zig build test`

## API & ghostmux quick hits

- **Bundle id:** `com.lherron.scriptableghostty` (`~/Applications/ScriptableGhostty.app`) — NOT upstream's `com.mitchellh.ghostty`, which `/Applications/Ghostty.app` carries. Frontmost-app checks that match only the upstream id fail silently; see "Reading Focus From Outside the Terminal" in ghostmux's `AGENTS.md`.
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

## Never run a second instance against a live one

There is exactly one UDS path, `~/Library/Application Support/Ghostty/api.sock`,
and no config or environment override for it. `APISocketServer.start()` unlinks
whatever is already at that path before binding, so **a second Ghostty instance
silently steals the socket from the running one**, and unlinks it again on exit.
The live instance keeps its now-orphaned listener fd and never rebinds, so
`ghostmux` stays broken even after the intruder is gone.

Overriding `HOME` does not isolate it. The Zig core reads config relative to
`$HOME`, but the socket path comes from `FileManager.urls(for:
.applicationSupportDirectory)` on the Swift side, which resolves the real user
record and ignores `$HOME`. A "sandboxed" second instance still lands on the real
socket. (Same failure mode as the Xcode test host — see the local memory note.)

**Recovery without restarting the app** (keeps every live session):

```bash
PID=$(pgrep -f 'ScriptableGhostty.app/Contents/MacOS/ghostty')
CFG=~/Library/Application\ Support/com.mitchellh.ghostty/config
cp "$CFG" /tmp/ghostty-config.bak

echo "macos-api-server = false" > "$CFG"   # tear the APIServer down...
kill -USR2 $PID                             # SIGUSR2 = reload config
sleep 2
cp /tmp/ghostty-config.bak "$CFG"           # ...and let it rebuild
kill -USR2 $PID
sleep 2
ghostmux status                             # available: true
```

This works because `AppDelegate.syncAPIServer` only constructs an `APIServer`
when the existing one is `nil`, so a plain reload will not rebind — the server
has to be turned off and back on. `SIGUSR2` triggers the reload
(`AppDelegate.swift`, `sigusr2` DispatchSource).

If you need to exercise a freshly built app, restart the installed one. There is
no side-by-side option today.

## Renderer memory: swap-chain targets

**See [`memfix.md`](memfix.md)** before touching renderer visibility,
`SwapChain`, or the macOS occlusion plumbing. Short version:

- Each of the 3 swap-chain frames owns a full surface-sized IOSurface-backed
  texture. At 6112x3069 that is ~72 MB per frame, ~216 MB per surface, so a
  window full of large tabs dominates the process footprint. Measure with
  `footprint -p <pid>`, not `vmmap` -- the memory is ledgered, not mapped.
- Off-screen surfaces release their targets via `Renderer.setVisible(false)` ->
  `SwapChain.shrinkTargets`, which drains `frame_sema` before freeing. Never
  free a target without that drain.
- `setVisible` holds `draw_mutex` across both the visibility store and the
  shrink, and `drawFrame` reads `visible` only after taking that mutex. The
  drain alone does not make the release stick -- a `drawFrame` already past the
  guard would just wait out the shrink and resize back to full size.
- `FrameState.resize` is not failure-atomic (it commits the custom shader
  textures before the fallible target allocation). `frame.sized` records
  whether a frame's sized resources agree; a false value forces `drawFrame` to
  redo the whole resize before rendering. Anything that changes a sized
  resource outside `resize` must clear the flag -- size resources through the
  single repair path rather than allocating them where you mutate.
- `Renderer.drawFrame` refuses to draw while invisible. That guard is
  load-bearing, not defensive: CoreAnimation calls `Metal.zig`'s
  `displayCallback` -> `drawFrame` directly for non-selected tabs, and without
  it every release is undone immediately.
- Visibility means **on screen**, not un-occluded. AppKit keeps a non-selected
  tab's window in `occlusionState.visible`. Anything that can change tab
  selection must call `syncTabGroupOcclusionState()`, not
  `syncSurfaceTreeOcclusionState()`.
- `SurfaceView.isWindowVisible` must start at `true` to match libghostty's
  `Surface.visible` default, or the first sync of an off-screen surface is
  skipped as a no-op.

To check visibility from inside a terminal, query DEC mode 2033: `CSI ? 998 n`
replies `CSI ? 999 ; 1 n` (potentially visible) or `CSI ? 999 ; 2 n` (not
visible).

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
