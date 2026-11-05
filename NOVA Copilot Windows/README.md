<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot icon" />
  <h1>NOVA Copilot for Windows</h1>
  <p><strong>Your AI copilot on Windows 10 and 11.</strong></p>
  <p><img alt="Windows version" src="https://img.shields.io/badge/version-1.1.0-2857C5?style=flat-square&logo=windows&logoColor=white" /> <img alt="Lenovo ThinkBook support" src="https://img.shields.io/badge/Lenovo-ThinkBook-263C63?style=flat-square" /></p>
  <p>Standalone Windows edition · Python / Tkinter · NOVA V8 backend</p>
</div>

---

## Download

Download the Windows package from the [NOVA Copilot Windows 1.1.0 release](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.1.0). Extract the ZIP and open **NOVA Copilot.exe**. Python is not required to run the packaged app.

Windows may show a SmartScreen warning because this free build is not signed with a paid code-signing certificate. Choose **More info → Run anyway** only if you downloaded the package from the NOVA GitHub release above.

## Features

| **Quick access** | **AI modes** | **Desktop controls** |
| --- | --- | --- |
| Floating panel, right-edge launcher and **Ctrl + Shift + Space**. | Fast, Hard Thinker and Coding, with streamed replies. | System tray, Keep on Top and optional Launch at Login. |

- Recent conversations and local chat history.
- Clipboard text is inserted only when you explicitly choose the clipboard action.
- Stops a response immediately in the interface, including while the connection is opening.
- Updates streamed text in place so long conversations remain responsive.
- Connects to the existing NOVA V8 chat backend.

## Build from source

To run from source, install Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/) and enable **Add Python to PATH** and the Python Launcher. Then run `run.bat`.

To build your own executable, run `build_windows.bat`. The script installs the pinned project dependencies and creates `dist\NOVA Copilot.exe`.

## Privacy and backend

- No API key is embedded in this Windows client.
- Chat requests are sent to `https://nova-v8.vercel.app/api/chat`.
- Conversation history is stored locally at `%LOCALAPPDATA%\NOVA Copilot\threads.json`.
- Clipboard contents are read only when you explicitly use the clipboard action.

See the [1.1.0 release notes](RELEASE_NOTES_v1.1.0.md) and [1.0.0 release notes](RELEASE_NOTES_v1.0.0.md).

---

[Back to platform selection](../README.md) · [macOS edition](../NOVA%20Copilot/README.md)
