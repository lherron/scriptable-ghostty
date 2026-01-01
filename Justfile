# ScriptableGhostty Build Configuration
# Custom build overrides for forked Ghostty

app_name := "ScriptableGhostty"
bundle_id := "com.lherron.scriptableghostty"
install_dir := env_var("HOME") / "Applications"
signing_identity := "Apple Development: Lance Herron (85G598CUAZ)"

# Default recipe - show available commands
default:
    @just --list

# Build the Zig core library (release mode)
build-zig:
    zig build -Doptimize=ReleaseFast

# Build ScriptableGhostty macOS app (Release)
build: build-zig
    @just _sync-icon-assets
    cd macos && xcodebuild \
        -scheme Ghostty \
        -configuration Release \
        SYMROOT="$(pwd)/build" \
        PRODUCT_NAME="{{ app_name }}" \
        PRODUCT_BUNDLE_IDENTIFIER="{{ bundle_id }}" \
        INFOPLIST_KEY_CFBundleDisplayName="{{ app_name }}" \
        INFOPLIST_KEY_CFBundleName="{{ app_name }}"

# Build without Zig rebuild (faster if only Swift changes)
build-swift:
    @just _sync-icon-assets
    cd macos && xcodebuild \
        -scheme Ghostty \
        -configuration Release \
        SYMROOT="$(pwd)/build" \
        PRODUCT_NAME="{{ app_name }}" \
        PRODUCT_BUNDLE_IDENTIFIER="{{ bundle_id }}" \
        INFOPLIST_KEY_CFBundleDisplayName="{{ app_name }}" \
        INFOPLIST_KEY_CFBundleName="{{ app_name }}"

# Install to ~/Applications (update in place to preserve TCC permissions)
install: build
    @mkdir -p "{{ install_dir }}"
    rsync -a --delete "macos/build/Release/{{ app_name }}.app/" "{{ install_dir }}/{{ app_name }}.app/"
    @just _replace-icon
    @just _resign
    @just _clear-icon-cache
    @echo "Installed to {{ install_dir }}/{{ app_name }}.app"

# Replace the app icon (generate icns from ScriptableGhostty png)
_replace-icon:
    #!/bin/bash
    set -e
    ICON_SRC="macos/Assets.xcassets/ScriptableGhosttyIcon.imageset/ScriptableGhostty-icon.png"
    if [ ! -f "$ICON_SRC" ]; then
        echo "No custom icon found at $ICON_SRC, skipping"
        exit 0
    fi
    APP="{{ install_dir }}/{{ app_name }}.app"
    if [ ! -d "$APP" ]; then
        echo "App not found at $APP, skipping"
        exit 0
    fi

    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    # Generate all required sizes
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    # Convert to icns
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    cp "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/Ghostty.icns"
    # Clear any custom icon metadata that can mask the bundle icon
    xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
    xattr -d com.apple.ResourceFork "$APP" 2>/dev/null || true
    rm -rf "$(dirname "$ICONSET")"
    echo "Custom icon installed"

# Sync ScriptableGhostty png into xcassets used by the app UI
_sync-icon-assets:
    #!/bin/bash
    set -e
    ICON_SRC="macos/Assets.xcassets/ScriptableGhosttyIcon.imageset/ScriptableGhostty-icon.png"
    if [ ! -f "$ICON_SRC" ]; then
        echo "No custom icon found at $ICON_SRC, skipping asset sync"
        exit 0
    fi
    APPICON_SET="macos/Assets.xcassets/AppIconImage.imageset"
    if [ ! -d "$APPICON_SET" ]; then
        echo "AppIconImage.imageset not found at $APPICON_SET, skipping asset sync"
        exit 0
    fi
    sips -z 256 256   "$ICON_SRC" --out "$APPICON_SET/macOS-AppIcon-256px-128pt@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$APPICON_SET/macOS-AppIcon-512px.png" >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$APPICON_SET/macOS-AppIcon-1024px.png" >/dev/null
    APPICON_APPSET="macos/Assets.xcassets/AppIcon.appiconset"
    if [ ! -d "$APPICON_APPSET" ]; then
        echo "AppIcon.appiconset not found at $APPICON_APPSET, skipping app icon sync"
        exit 0
    fi
    sips -z 16 16     "$ICON_SRC" --out "$APPICON_APPSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$APPICON_APPSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$APPICON_APPSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$APPICON_APPSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$APPICON_APPSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$APPICON_APPSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$APPICON_APPSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$APPICON_APPSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$APPICON_APPSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$APPICON_APPSET/icon_512x512@2x.png" >/dev/null
    echo "xcasset icons updated"

# Clear icon cache for ScriptableGhostty
_clear-icon-cache:
    #!/bin/bash
    set -e
    APP="{{ install_dir }}/{{ app_name }}.app"
    if [ ! -d "$APP" ]; then
        echo "App not found at $APP, skipping icon cache clear"
        exit 0
    fi
    touch "$APP"
    # Re-register with LaunchServices (best-effort)
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$APP" >/dev/null 2>&1 || true
    # Clear cached custom icon metadata stored by the app
    defaults delete "{{ bundle_id }}" CustomGhosttyIcon >/dev/null 2>&1 || true
    defaults delete "{{ bundle_id }}" CustomGhosttyIconBuild >/dev/null 2>&1 || true
    # Clear per-user icon caches
    rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    rm -rf ~/Library/Caches/com.apple.iconservices 2>/dev/null || true
    rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null || true
    rm -rf /var/folders/*/*/com.apple.iconservices 2>/dev/null || true
    rm -rf /var/folders/*/*/com.apple.dock.iconcache 2>/dev/null || true
    # Restart icon services/Dock/Finder to pick up the new icon
    killall -u "$USER" iconservicesagent 2>/dev/null || true
    killall -u "$USER" Dock 2>/dev/null || true
    killall -u "$USER" Finder 2>/dev/null || true
    echo "Icon caches cleared"

# Re-sign the installed app (fixes Sparkle framework signature mismatch)
_resign:
    #!/bin/bash
    APP="{{ install_dir }}/{{ app_name }}.app"
    IDENTITY="{{ signing_identity }}"
    # Sign Sparkle's nested components first
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
    # Sign the main app
    codesign --force --sign "$IDENTITY" "$APP"

# Build ScriptableGhostty macOS app (Debug) and run it
debug:
    zig build
    @just _sync-icon-assets
    cd macos && xcodebuild \
        -scheme Ghostty \
        -configuration Debug \
        SYMROOT="$(pwd)/build" \
        PRODUCT_NAME="{{ app_name }}" \
        PRODUCT_BUNDLE_IDENTIFIER="{{ bundle_id }}" \
        INFOPLIST_KEY_CFBundleDisplayName="{{ app_name }}" \
        INFOPLIST_KEY_CFBundleName="{{ app_name }}"
    open "macos/build/Debug/{{ app_name }}.app"

# Run the built app (without installing)
run: build
    open "macos/build/Release/{{ app_name }}.app"

# Run the installed app
run-installed:
    open "{{ install_dir }}/{{ app_name }}.app"

# Restart the installed app (kill and reopen)
restart:
    -pkill -f "{{ app_name }}.app"
    @sleep 1
    open "{{ install_dir }}/{{ app_name }}.app"

# Generate website documentation (config reference, actions, commands)
docs:
    zig build -Demit-webdata=true
    cp zig-out/share/ghostty/webdata/config.mdx ~/projects/ghostmux/ghostty_config.mdx
    cp zig-out/share/ghostty/webdata/actions.mdx ~/projects/ghostmux/ghostty_actions.mdx
    cp zig-out/share/ghostty/webdata/commands.mdx ~/projects/ghostmux/ghostty_commands.mdx
    @echo "Generated and copied docs to ~/projects/ghostmux/"

# Clean build artifacts
clean:
    rm -rf zig-out zig-cache
    cd macos && xcodebuild clean -scheme Ghostty

# Clean only Xcode build
clean-xcode:
    cd macos && xcodebuild clean -scheme Ghostty
    rm -rf macos/build

# Build upstream Ghostty (unmodified, for comparison)
build-upstream:
    zig build
    cd macos && xcodebuild -scheme Ghostty -configuration Release

# Show what would be built
info:
    @echo "App Name:   {{ app_name }}"
    @echo "Bundle ID:  {{ bundle_id }}"
    @echo "Install To: {{ install_dir }}/{{ app_name }}.app"
