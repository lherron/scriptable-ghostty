# Renderer memory: releasing swap-chain targets for off-screen surfaces

Why a running ScriptableGhostty reached 11 GB, and the four changes that brought
a comparable layout down by 10x. Read this before touching renderer visibility,
`SwapChain`, or the macOS occlusion plumbing.

Tracked as wrkq `T-07389`.

## The measurement

A ScriptableGhostty that had been up ~2 days with 56 open surfaces:

```
ghostty [49998]  phys_footprint: 11 GB (peak 12 GB)

9163 MB   198 regions   IOSurface                      <- 82% of the footprint
1200 MB  1260 regions   unmapped (graphics)
 531 MB   189 regions   MALLOC_SMALL
 306 MB  1378 regions   IOAccelerator (graphics)
```

The mapped `IOSurface` VM regions are all 16K stubs. The 9.1 GB is GPU-side
surface memory ledgered to the process, so `vmmap` alone will not show it --
use `footprint -p <pid>`.

## Where it came from

`swap_chain_count = 3` (`src/renderer/Metal.zig`). Every `FrameState` owns a
full surface-sized IOSurface-backed `MTLTexture` (`src/renderer/metal/Target.zig`,
32BGRA, 4 bytes/px). Targets start at 1x1 and grow to screen size on first draw
via the size check in `drawFrame` (`src/renderer/generic.zig`). Before this work
they were never shrunk or released for the life of the renderer.

40 of those 56 surfaces were tabs of a single window at 6112x3069 px -- 382 cols
x 16 px cells, 93 rows x 33 px cells:

```
 27 surfaces  6112x3069   72 MB each
 13 surfaces  6112x3135   73 MB each
 14 surfaces  smaller
                           x 3 swap-chain targets  =  8.86 GB
```

Against 8.95 GB measured. Accounted for.

To sanity-check this on a live process, predict from surface geometry and
compare to the `IOSurface` line:

```bash
ghostmux ls --json | python3 -c "
import json,sys
t=json.load(sys.stdin)['terminals']
b=sum(x['columns']*x['cell_width']*x['rows']*x['cell_height']*4 for x in t)
print(f'{len(t)} surfaces, 3x targets = {3*b/1073741824:.2f} GB')"
footprint -p $(pgrep -f 'ScriptableGhostty.app/Contents/MacOS/scriptable-ghostty') | head -8
```

## Two defects, not one

**D1. Occlusion never fired for background tabs.** Visibility came only from
`NSWindow.occlusionState`. Ghostty tabs are native `NSWindowTabGroup` windows,
and AppKit keeps the window of a *non-selected* tab inside
`occlusionState.visible`. So a background tab was reported on screen, kept
rendering, and kept its targets.

Verified with a DEC mode 2033 probe rather than by reading AppKit docs. From
inside a terminal, `CSI ? 998 n` replies `CSI ? 999 ; 1 n` (potentially visible)
or `CSI ? 999 ; 2 n` (not visible):

```bash
old=$(stty -g); stty raw -echo min 0 time 3
printf '\033[?998n' > /dev/tty; IFS= read -r -d 'n' reply < /dev/tty
stty "$old"; printf '%q\n' "$reply"
```

**D2. Occlusion was pause-only.** `ghostty_surface_set_occlusion` stopped the
render thread drawing; nothing ever freed GPU state.

## The changes

C1 and C4 are the design. C2 and C3 exist because C1+C4 alone recovered
*exactly zero bytes*, twice. C5 and C6 close two failure paths daedalus named in
review. Do not remove any of them on the theory that they are defensive -- each
one is load-bearing for a stated invariant.

### C1 -- release the targets (`src/renderer/generic.zig`)

`SwapChain.shrinkTargets(api)` drains all `buf_count` permits from `frame_sema`
-- the same pattern `SwapChain.deinit` uses -- so no in-flight GPU frame is
freed underneath it, then calls `frame.resize(api, 1, 1)` on every frame.

Called from `Renderer.setVisible(false)`, which holds `draw_mutex` across both
the visibility store and the shrink. **Both parts of that are required**, see
C5.

The drain alone is not enough, and `resize` is not atomic; see C5 and C6.

### C2 -- refuse to draw while invisible (`src/renderer/generic.zig`)

`Renderer.drawFrame` early-returns when `!self.visible`.

**This is load-bearing.** `renderer.Thread.drawFrame` has its own visibility
guard, but it is not the only caller: on macOS, `Metal.zig`'s `displayCallback`
calls `renderer.drawFrame(true)` directly whenever CoreAnimation wants a layer's
contents, and CoreAnimation does that for the layers of non-selected tabs.
Without this guard, CA re-display immediately reallocated every target C1 had
just freed, and the net saving was zero.

Skipping the draw does not blank the tab: `CALayer` retains the last IOSurface
it was handed as its `contents`, independently of our swap-chain references.

### C3 -- order `setVisible` before the redraw (`src/renderer/Thread.zig`)

In the `.visible` mailbox handler, `renderer.setVisible(v)` now runs *above* the
`if (v) { updateFrame; drawFrame }` block. It used to run after. With C2 in
place that ordering would drop the first frame back, leaving a stale tab until
the next damage event.

### C4 -- visibility means on screen, not un-occluded (macOS)

- `BaseTerminalController.isSurfaceTreeOnScreen` =
  `occlusionState.contains(.visible)` **and** (untabbed **or**
  `tabGroup.selectedWindow == window`). Guarded behind `window.tabbedWindows`
  (nil when untabbed) so the common path never materializes the tab group --
  that costs 15-20 ms per window creation, see the note at
  `TerminalController.swift:1166`.

- `syncTabGroupOcclusionState()` refreshes every controller in the tab group.
  Selecting a tab changes two windows' on-screen state at once and AppKit posts
  no notification for it, so anything that can change tab selection must call
  this, **not** `syncSurfaceTreeOcclusionState()`. Call sites:
  `windowDidChangeOcclusionState`, `surfaceTreeDidChange`, the deferred branch
  of `windowDidBecomeKey` (selection has settled by then), and the end of
  `newTab`'s `scheduleInitialPresentation` (covers tabs created in the
  background, which is how hrc/ghostmux create them).

- `SurfaceView.isWindowVisible` default flipped `false` -> `true`. That field
  mirrors what we last told libghostty, and libghostty's `Surface.visible`
  defaults to `true`. Starting at `false` made the first sync of a genuinely
  off-screen surface compare equal and skip the `ghostty_surface_set_occlusion`
  call entirely, leaving the core believing it was visible. This alone kept
  every background-created tab at full size.

### C5 -- serialize the transition with `drawFrame` (`src/renderer/generic.zig`)

`draw_mutex`'s contract is that it covers every mutation *and* read of state
used by `drawFrame`. Two changes bring the visibility transition under it:

- `drawFrame` reads `visible` **after** acquiring `draw_mutex`, not before.
- `setVisible` holds `draw_mutex` across both the `visible` store and
  `shrinkTargets`.

Without this, the release does not stick and I2 is false. `drawFrame` could pass
the visibility guard while still visible, block on the semaphore that
`shrinkTargets` had drained, then continue once the shrink completed and resize
its frame straight back to full size. The unsynchronized cross-thread read of
`visible` was also a data race under the stated contract. The CoreAnimation
display callback (C2) is exactly the caller that runs independently of the
render thread and hits this.

This cannot deadlock against the semaphore drain: permits held by in-flight GPU
frames are returned by `frameCompleted`, which takes no locks.

### C6 -- track frame resource consistency (`src/renderer/generic.zig`)

`FrameState.resize` is **not** failure-atomic. It commits the custom shader
textures first (`CustomShaderState.resize` releases the old textures when it
commits) and only then performs the fallible target allocation, which can fail
with `OutOfMemory` or `MetalFailed`. A failure there leaves 1x1 shader textures
paired with the old full-size target -- and the repair condition in `drawFrame`
compared only target dimensions, so it could not detect that and would render
through wrong-sized intermediates. That breaks I3.

`FrameState` now carries a `sized` flag: `resize` clears it on entry and sets it
only on complete success, and the repair condition in `drawFrame` treats
`!frame.sized` as needing a full resize. A failed shrink therefore forces the
next draw to redo the whole resize; if that fails too, `try` propagates and the
frame is not rendered at all.

For the flag to mean anything it has to be authoritative, so **every** mutation
of a sized resource has to go through `resize` or clear it. One did not:
`drawFrame` attaches a fresh `custom_shader_state` when custom shaders get
enabled at runtime (reachable via `changeConfig` -> `initShaders` ->
`has_custom_shaders`), and it used to size those 1x1 textures itself with a
second fallible allocation. A failure there left `sized` true beside a
correctly sized target, so the repair condition would skip and render through
1x1 intermediates.

That direct resize is gone. `drawFrame` now just clears `frame.sized` and
attaches the fresh state, letting the one repair path size the textures and the
target together. Dropping a state does not need the same treatment -- with
nothing left to disagree with the target, the frame stays consistent.

This only bites when custom shaders are configured, but it is reachable.

## Invariants

- A target is never freed while a GPU frame is in flight against it --
  `frame_sema` is fully drained before any `deinit`.
- A surface that is not on screen holds no full-size render target. The drain
  alone does not give this; `draw_mutex` held across the shrink (C5) does.
- Every sized resource in a frame agrees with every other, or `frame.sized` is
  false and the next draw repairs all of them before rendering (C6).
- A surface that is on screen always has correctly sized targets: `drawFrame`'s
  size check reallocates, and C3 guarantees a draw on the invisible->visible
  edge.
- Skipping a draw never blanks a tab, because the layer retains its last
  `contents` surface.

## Result

10 tabs at 6112x3201 px in one window, one selected:

```
before   IOSurface 2229 MB   footprint 2904 MB
after    IOSurface  223 MB   footprint  689 MB
```

Background tabs hold zero full-size targets. A tab created in the background
never draws a full frame at all, so there is not even a retained layer surface
for it.

Validated on the real installed app:

- Re-selecting a background tab renders correctly -- marker text, prompt and
  cursor all present, no blanking.
- Resize while hidden: a tab went 95 -> 101 rows off screen, then rendered
  correctly at the new 6144x3384 fullscreen size with content intact.
- Steady state holds across tab switching -- footprint stays flat as one tab
  allocates and the other releases.

## Out of scope

Clearing `CALayer.contents` for off-screen surfaces. It would also release the
retained last-frame surface, at the cost of a visible flash on tab re-select.
With C2 in place the remaining benefit is small, since background-created tabs
never allocate one.
