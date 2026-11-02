# NOVA Copilot for Windows

**Version 1.0.0 · Windows 10 / Windows 11 · Lenovo ThinkPad and other PCs**

This is the standalone Windows edition of NOVA Copilot. It is a Python/Tkinter port and is separate from the native macOS Swift application.

## Features

- Floating assistant panel and right-edge launcher.
- Global shortcut: **Ctrl + Shift + Space**.
- Windows notification-area (system tray) icon.
- Streaming replies through the existing Nova V8 backend.
- Fast, Hard Thinker, and Coding modes.
- Recent conversations and local chat history.
- Clipboard text inserted only when requested.
- Keep on top and optional Launch at Login.

## Install and build on Windows

1. Download or clone this repository and open the **NOVA Copilot Windows** folder.
2. Install **Python 3.10 or newer** from [python.org](https://www.python.org/downloads/windows/). Enable **Add Python to PATH** during setup.
3. Double-click `build_windows.bat`.
4. When the build finishes, open `dist\NOVA Copilot.exe`.

To run from source without creating an executable, double-click `run.bat`.

## Executable and signing status

- The Windows executable is generated locally by the build script; it is not prebuilt in the repository.
- The source passed a ZIP integrity check and Python syntax compilation, but it has not yet been built or tested on a physical ThinkPad.
- The generated executable is not signed with a publicly trusted code-signing certificate. Windows SmartScreen may show a warning.

## Privacy and backend

- No API key is embedded in this Windows client.
- Chat requests are sent to `https://nova-v8.vercel.app/api/chat`.
- Conversation history is stored locally at `%LOCALAPPDATA%\NOVA Copilot\threads.json`.
- Clipboard contents are read only when you explicitly use the clipboard action.

## Release notes

See [Windows 1.0.0 release notes](RELEASE_NOTES_v1.0.0.md).

---

[Back to platform selection](../README.md) · [macOS edition](../NOVA%20Copilot/README.md)
