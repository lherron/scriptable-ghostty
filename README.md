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
