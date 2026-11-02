<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot original app icon" />
  <h1>NOVA Copilot for Windows</h1>
  <p><strong>Your AI copilot on Windows 10 and 11.</strong></p>
  <p><img alt="Windows version" src="https://img.shields.io/badge/version-1.0.0-2857C5?style=flat-square&logo=windows&logoColor=white" /> <img alt="ThinkPad support" src="https://img.shields.io/badge/Lenovo-ThinkPad-263C63?style=flat-square" /></p>
  <p>Standalone Windows edition · Python / Tkinter · NOVA V8 backend</p>
</div>

---

## Your NOVA assistant, on your PC

This is the independent Windows edition of NOVA Copilot. It is designed for Lenovo ThinkPad laptops and other Windows PCs. It is not the native macOS Swift application.

## Features

| **Quick access** | **AI modes** | **Desktop controls** |
| --- | --- | --- |
| Floating panel, right-edge launcher and **Ctrl + Shift + Space**. | Fast, Hard Thinker and Coding, with streamed replies. | System tray, Keep on Top and optional Launch at Login. |

- Recent conversations and local chat history.
- Clipboard text inserted only when you explicitly request it.
- Connects to the existing NOVA V8 chat backend.

## Install and build on Windows

1. Download or clone this repository and open the **NOVA Copilot Windows** folder.
2. Install **Python 3.10 or newer** from [python.org](https://www.python.org/downloads/windows/). Enable **Add Python to PATH** during setup.
3. Double-click `build_windows.bat`.
4. When the build finishes, open `dist\NOVA Copilot.exe`.

To run from source without creating an executable, double-click `run.bat`.

## Executable and signing status

- The executable is generated locally by the build script; it is not prebuilt in the repository.
- The source has passed a ZIP integrity check and Python syntax compilation, but has not yet been built or tested on a physical ThinkPad.
- The generated executable is not signed with a publicly trusted code-signing certificate. Windows SmartScreen may show a warning.

## Privacy and backend

- No API key is embedded in this Windows client.
- Chat requests are sent to `https://nova-v8.vercel.app/api/chat`.
- Conversation history is stored locally at `%LOCALAPPDATA%\NOVA Copilot\threads.json`.
- Clipboard contents are read only when you explicitly use the clipboard action.

## Source files

- `app.py` — Windows desktop assistant.
- `requirements.txt` — Python dependencies.
- `build_windows.bat` — create the Windows executable.
- `run.bat` — run from source.

See [Windows 1.0.0 release notes](RELEASE_NOTES_v1.0.0.md).

---

[Back to platform selection](../README.md) · [macOS edition](../NOVA%20Copilot/README.md)
