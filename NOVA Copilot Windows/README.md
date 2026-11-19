<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot icon" />
  <h1>NOVA Copilot for Windows</h1>
  <p><strong>Your AI copilot on Windows 10 and 11.</strong></p>
  <p><img alt="Windows source version" src="https://img.shields.io/badge/source-1.7.0-2857C5?style=flat-square&logo=windows&logoColor=white" /></p>
  <p>Standalone Windows edition · Python / Tkinter · NOVA V8 backend</p>
  <p>Source version 1.7.0 adds a command palette, per-app mode defaults, monitor-aware placement and a reviewed code-patch workflow. NOVA starts a guest profile automatically; signing in to an existing Google or email/password account is optional.</p>
</div>

---

## Download

Download and open the [standalone NOVA Copilot for Windows (1.7.0)](https://github.com/Ethan-cat-a/NOVA/releases/download/windows-v1.7.0/NOVA-Copilot-Windows-1.7.0.exe). It runs without Python or ZIP extraction.

Windows SmartScreen may warn because this free build is unsigned. Choose **More info → Run anyway** only if you downloaded the EXE from the official NOVA GitHub release.

## Features

- Floating panel, right-edge launcher, system tray and **Ctrl + Shift + Space** shortcut.
- Fast, Hard Thinker and Coding modes, with streamed replies, a visible thinking/writing status and a labeled Stop button.
- Copy completed replies and try the latest reply again in its original mode.
- **Word Doc** mode to draft a document or fill an attached `.docx`; review and edit the result before saving a new `.docx`.
- Choose a clean Word export style: Clean, Report, Study guide or Meeting notes. Review and edit the draft before saving; the original document's layout is not copied.
- Preview extracted text from `.docx` files and PDFs before sending it to NOVA. Only the extracted text is sent; the original file stays on this PC.
- Install a per-user **Send to NOVA** item in File Explorer, then select up to five supported documents or source files for a text preview before attaching them.
- Choose **Project folder (read-only)** to preview up to 12 source/project files (96 KB each, 15,000 characters total). Common environment/credential names and build/dependency folders are skipped; inspect the preview for sensitive text before attaching it.
- Explain copied PowerShell, Command Prompt or Windows Terminal errors in Coding mode. NOVA suggests troubleshooting steps but does not run commands.
- Open a keyboard-first command palette with **Ctrl + K**. Filter commands, move with arrow keys and run with Enter.
- Save a default NOVA mode for the app you opened NOVA from. Defaults apply to new chats; NOVA reads only the app's executable name.
- Keep the panel and edge handle inside the active monitor's work area, away from the taskbar, and remember the panel position for each monitor.
- Ask NOVA for a project patch, inspect the unified diff, select each file to approve, and apply only the chosen edits. NOVA checks that files have not changed and saves recoverable backups first; it does not run commands or add/delete files.
- Increase or decrease text size with **Ctrl + =** and **Ctrl + -**. Use **Ctrl + Tab** and **Ctrl + Shift + Tab** to move between controls while preserving Tab's normal text-editing behavior.
- Export any reply to Word with a chosen style, edit it first, then save and open it in the default `.docx` app.
- Copy the first code block from a reply with its **Copy code** action.
- Summarize or rewrite copied text after previewing it.
- A visible **Update** button checks the latest Windows release and opens its GitHub page when you approve. Updates are downloaded and installed manually.
- Recent conversations, local chat history, Keep on Top and optional Launch at Login.
- Guest and regular profiles receive 25 chat requests per UTC day, enforced by the server. A one-time owner code can activate the private unlimited-use profile.
- Guest usage is attached to a device profile. Clearing NOVA’s saved app data can create a new profile and allowance.
- Temporary network or refresh-service errors no longer discard a saved account session. A known expired guest refresh token is replaced automatically; an expired signed-in account asks you to sign in again.

Windows supports `.docx` files and PDFs with selectable text. Scanned PDF OCR, image OCR and screen/window capture are not available in this Windows build. Word export creates a new `.docx` with a selected heading and list style; it does not preserve the source document’s formatting, tables or images. Project-folder reading is local and read-only, and text is sent only after you review, attach and send a message. Attached excerpts remain in local chat history. Patch backups are kept under `%LOCALAPPDATA%\NOVA Copilot\patch-backups`.

## Build from source

Install Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/) and enable **Add Python to PATH** and the Python Launcher. Then run `run.bat`.

To build your own executable, run `build_windows.bat`. The script installs the project dependencies and creates `dist\NOVA Copilot.exe`.

## Privacy and backend

- No NOVA/OpenRouter model key is embedded in this Windows client.
- Chat requests are sent to the NOVA Copilot gateway, which verifies the account and forwards the existing NOVA V8 response.
- The Supabase publishable key is used only for account authentication; access and refresh tokens are protected with Windows DPAPI.
- Conversation history is stored locally at `%LOCALAPPDATA%\NOVA Copilot\threads.json`.
- Clipboard contents are read only when you choose a clipboard action.
- Word, PDF, Explorer-selected files and project-folder files are read locally; only reviewed extracted text is included when you attach it and send a message. Explorer input is limited to five files at once and 12 MB per file.

Google sign-in uses Supabase Auth in your system browser. The first project setup requires Google OAuth credentials and the loopback callback URL in Supabase; see the [setup guide](../GOOGLE_SIGN_IN_SETUP.md). The Google client secret stays in Supabase and is never included in the app.

See the [1.7.0 source notes](RELEASE_NOTES_v1.7.0.md), [1.6.0 source notes](RELEASE_NOTES_v1.6.0.md), [1.5.3 release notes](RELEASE_NOTES_v1.5.3.md), [1.5.2 release notes](RELEASE_NOTES_v1.5.2.md), [1.5.1 source notes](RELEASE_NOTES_v1.5.1.md), [1.5.0 release notes](RELEASE_NOTES_v1.5.0.md) and [1.4.2 release notes](RELEASE_NOTES_v1.4.2.md).

---

[Back to platform selection](../README.md) · [macOS edition](../NOVA%20Copilot/README.md)
