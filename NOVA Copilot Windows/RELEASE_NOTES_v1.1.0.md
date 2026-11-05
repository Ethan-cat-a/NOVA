# NOVA Copilot for Windows 1.1.0

**Release channel:** Windows  
**Target systems:** Windows 10 and Windows 11  
**Supported hardware:** Lenovo ThinkBook, ThinkPad and compatible Windows PCs

## What’s new

- Adds a downloadable, self-contained Windows application; Python is no longer needed to run the release package.
- Makes Stop immediately release the interface so another message can be sent even while a connection attempt is winding down.
- Updates streamed replies in place instead of rebuilding the entire conversation after every update.
- Keeps the current scroll position unless the user was already at the bottom of the conversation.
- Adds focused tests for cancellation, UTF-8 streaming and incremental rendering.

## Install

Download `NOVA-Copilot-Windows-1.1.0.zip` from the [Windows 1.1.0 release](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.1.0), extract it, and run `NOVA Copilot.exe`.

The application is not signed with a publicly trusted Windows code-signing certificate. Windows SmartScreen may display a warning.

## Validation

- Windows CI runs the focused Python tests and builds the release executable.
- A physical Lenovo ThinkBook has not been tested as part of this release.
