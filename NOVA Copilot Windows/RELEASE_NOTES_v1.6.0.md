# NOVA Copilot for Windows 1.6.0

Windows source update notes · 2026-11-18

## New

- Add a per-user File Explorer **Send to NOVA** shortcut. Choose supported files, review extracted text and attach it only when ready.
- Add opt-in, read-only project-folder context. NOVA previews up to 12 source or project files (96 KB each, 15,000 characters total), skips common environment and credential names plus build/dependency folders, and sends nothing until the user attaches the preview and sends a message. Review the preview for any other sensitive text.
- Add **Explain copied terminal error** for PowerShell, Command Prompt and Windows Terminal output. It asks NOVA to explain likely causes and suggest safe troubleshooting; it does not execute commands.
- Add four Word export styles: Clean, Report, Study guide and Meeting notes. The reviewed editor remains in control, and exports use a new `.docx` rather than modifying an existing file.
- Let File Explorer input handle up to five selected files at once, with a 12 MB per-file limit.

## Reliability

- Preserve the saved guest or signed-in profile when token refresh fails due to a temporary network or service problem. Only recognized expired or invalid refresh-token responses trigger session recovery.

## Download status

These are source changes for Windows 1.6.0. The latest published Windows installer remains 1.5.3 until the 1.6.0 executable is built and released. See the [Windows guide](README.md) for the current installer and build instructions.
