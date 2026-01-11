# send-keys Enter Bug Investigation

## Original Problem
`ghostty send-keys --enter` was not sending the Enter key. A separate call with `ghostty send-keys Enter` worked correctly.

## Root Cause
In `SendKeysCommand.swift`, the validation at line 62-64 checked if `positional.isEmpty` and threw an error BEFORE the `--enter` flag was processed into keystrokes. So `--enter` alone would fail.

## Solution Approach
Changed behavior so Enter is always sent by default:
1. Removed `--enter` flag
2. Added `--no-enter` flag to opt out
3. Enter is sent as a separate API call after the text keys (using `strokesForToken("Enter")`)

## Current State of Changes

### Files Modified

**`macos/Tools/ghostmux/Commands/SendKeysCommand.swift`:**
- Removed `--enter` flag parsing
- Added `--no-enter` flag parsing
- Added 5ms delay between keystrokes: `usleep(5000)`
- Added 50ms delay before Enter: `usleep(50000)`
- Send Enter as separate API call after all text keys

**`macos/Tools/ghostmux/KeyStroke.swift`:**
- Enter keystroke uses: `text: "\n", unshiftedCodepoint: 0x0A`

## New Issue Introduced
After adding the 5ms inter-keystroke delay (to prevent character dropping in TUIs), shifted characters are broken:
- `+` is being received as `=` (the unshifted version)
- Before the delay was added, characters were being dropped but shifted chars worked
- With delay, fewer characters dropped but shift modifier not applied

## Test Results

### Working:
- `ghostmux send-keys "echo test"` in shell - Enter sent correctly
- `ghostmux send-keys "say hello world"` in Claude Code TUI - works with delay
- `ghostmux send-keys "/exit"` in Claude Code - works

### Not Working:
- `ghostmux send-keys "what is 2+2"` becomes "what is 2=2" (shift lost on +)

## Key Code Locations

### SendKeysCommand.swift (current state):
```swift
for stroke in strokes {
    try context.client.sendKey(terminalId: targetTerminal.id, stroke: stroke)
    usleep(5000)  // 5ms between keystrokes for TUI compatibility
}

// Send Enter as a separate call unless --no-enter was specified
if !noEnter {
    usleep(50000)  // 50ms delay before Enter
    let enterStrokes = try strokesForToken("Enter")
    for stroke in enterStrokes {
        try context.client.sendKey(terminalId: targetTerminal.id, stroke: stroke)
    }
}
```

### KeyStroke.swift - How '+' is encoded:
```swift
case "+": return KeyStroke(key: "equal", mods: ["shift"], text: "+", unshiftedCodepoint: 0x3D)
```

### API sends this JSON for '+':
```json
{
  "key": "equal",
  "mods": ["shift"],
  "text": "+",
  "unshifted_codepoint": 61
}
```

## Questions to Investigate
1. Why does the delay cause shift modifiers to be lost?
2. Is the delay being applied incorrectly (maybe affecting the previous keystroke's modifier state)?
3. Should we use a different approach - maybe batch keys or use the `/input` text endpoint instead of `/key` for regular text?
4. Is there a way to send text without per-key events that would avoid timing issues?

## Alternative Approaches to Consider
1. Use `/terminals/{id}/input` endpoint for text, only use `/key` for Enter
2. Remove inter-keystroke delay, only keep delay before Enter
3. Investigate if the terminal/TUI needs key-up events after shifted keys

## How to Rebuild and Test
```bash
just install-ghostmux
ghostmux list-surfaces  # get terminal ID
ghostmux send-keys -t <ID> "test message"
ghostmux capture-pane -t <ID>
```
