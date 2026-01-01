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

## Upstream

This fork tracks upstream Ghostty. For documentation on terminal features, configuration, and general usage, see the [Ghostty documentation](https://ghostty.org/docs).
