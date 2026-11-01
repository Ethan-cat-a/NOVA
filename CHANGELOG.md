# NOVA Copilot Version 1.1.2

- Runs as a regular macOS app with a Dock icon while retaining the menu-bar sparkle and global shortcut.
- Adds a standard app menu and a Dock-click reopen action for the floating panel.
- Uses the macOS template sparkle glyph for reliable light/dark menu-bar contrast.
- Enables the hardened runtime for Release builds to prepare for Apple notarization.
- Documents the Developer ID signing and notarization steps required for a no-warning shareable build.
- Sets the marketing version to 1.1.2 and build number to 2.

# NOVA Copilot Version 1.1.1

- Based on Version 1.1.0 and retains the original AppKit `NSApplication` / `AppDelegate` startup architecture.
- Adds an explicit, standard Xcode `BuildableProductRunnable` to the shared scheme's `LaunchAction`, pointing to the existing `NOVA Copilot.app` target (blueprint ID `E10000000000000000000001`).
- Keeps the original product name, bundle identifier, executable naming, entitlements, target membership, source files, and assets.
- Retains the `NovaChatModel` initializer correction, Carbon buffer-size type correction, immutable hot-key ID, and removal of redundant `await` expressions.
- Sets the marketing version to 1.1.1.

Validation performed: project/scheme structure and references, property-list entitlements, asset JSON and referenced image files, Swift syntax parsing, and ZIP integrity. A native macOS Xcode build and launch cannot be executed in this environment and must still be verified on macOS.
