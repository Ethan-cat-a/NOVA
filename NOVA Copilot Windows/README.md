<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot icon" />
  <h1>NOVA Copilot for Windows</h1>
  <p><strong>Your AI copilot on Windows 10 and 11.</strong></p>
  <p><img alt="Windows version" src="https://img.shields.io/badge/version-1.4.2-2857C5?style=flat-square&logo=windows&logoColor=white" /></p>
  <p>Standalone Windows edition · Python / Tkinter · NOVA V8 backend</p>
</div>

---

## Download

Download the [NOVA Copilot for Windows 1.4.2 ZIP](https://github.com/Ethan-cat-a/NOVA/releases/download/windows-v1.4.2/NOVA-Copilot-Windows-1.4.2.zip), extract it, and open **NOVA Copilot.exe**. Python is not required to run the packaged app.

Windows SmartScreen may warn because this free build is unsigned. Choose **More info → Run anyway** only if you downloaded the ZIP from the official NOVA GitHub release.

## Features

- Floating panel, right-edge launcher, system tray and **Ctrl + Shift + Space** shortcut.
- Fast, Hard Thinker and Coding modes, with streamed replies, a visible thinking/writing status and a labeled Stop button.
- Copy completed replies and try the latest reply again in its original mode.
- **Word Doc** mode to draft a document or fill an attached `.docx`; review and edit the result before saving a new `.docx`.
- Preview extracted text from `.docx` files and PDFs before sending it to NOVA. Only the extracted text is sent; the original file stays on this PC.
- Summarize or rewrite copied text after previewing it.
- A visible **Update** button checks the latest Windows release and opens its GitHub page when you approve. Updates are downloaded and installed manually.
- Recent conversations, local chat history, Keep on Top and optional Launch at Login.

Windows supports `.docx` files and PDFs with selectable text. Scanned PDF OCR, image OCR and screen/window capture are not available in this Windows build. Word export creates a new text-based `.docx`; it does not preserve the source document’s formatting, tables or images.

## Build from source

Install Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/) and enable **Add Python to PATH** and the Python Launcher. Then run `run.bat`.

To build your own executable, run `build_windows.bat`. The script installs the project dependencies and creates `dist\NOVA Copilot.exe`.

## Privacy and backend

- No API key is embedded in this Windows client.
- Chat requests are sent to `https://nova-v8.vercel.app/api/chat`.
- Conversation history is stored locally at `%LOCALAPPDATA%\NOVA Copilot\threads.json`.
- Clipboard contents are read only when you choose a clipboard action.
- Word and PDF files are read locally; only reviewed extracted text is included when you send a message.

See the [1.4.2 release notes](RELEASE_NOTES_v1.4.2.md) and [1.1.0 release notes](RELEASE_NOTES_v1.1.0.md).

---

[Back to platform selection](../README.md) · [macOS edition](../NOVA%20Copilot/README.md)
