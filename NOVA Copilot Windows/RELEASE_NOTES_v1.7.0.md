# NOVA Copilot for Windows 1.7.0

Windows source update notes · 2026-11-18

## Workflow

- Open the **Ctrl+K command palette** to search actions, navigate with arrow keys and run with Enter.
- Assign Fast, Hard Thinker or Coding as the default for the active app. NOVA records only the executable name and applies the preference to new chats.
- Choose **Propose project patch** to share a bounded preview of a folder you selected. NOVA returns a unified diff for existing files only.
- Review each file's diff and select which files to apply. NOVA verifies the original files have not changed, saves copies under `%LOCALAPPDATA%\NOVA Copilot\patch-backups`, and writes only the selected files. It does not add/delete files or run commands.
- Export any response to Word, edit it, choose a document style, then save and open the `.docx` with the default Windows app.
- Copy the first fenced code block in a reply with **Copy code**. Terminal explanations ask for PowerShell commands in separate, reviewable code blocks; NOVA never executes them.

## Windows polish

- Remember the panel position for each display and place it within that display's work area to stay clear of the taskbar.
- Increase/decrease text size with **Ctrl+=** and **Ctrl+-**. Cycle controls with **Ctrl+Tab** and **Ctrl+Shift+Tab**, and open commands with Ctrl+K.

## Safety and scope

- Patch generation uses only a folder the user selected and previews at most 12 files of up to 96 KB each and 15,000 characters. The scan examines up to 5,000 entries.
- Patch application rejects paths outside the selected folder, files not in the reviewed preview, file creation/deletion/rename, stale source contents and malformed diffs. Each selected file requires explicit approval; backups are saved before changes.
- App mode preferences store executable names only. NOVA does not read the foreground app's contents.

## Download

The standalone Windows installer is available on the [1.7.0 GitHub release](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.7.0). See the [Windows guide](README.md) for installation instructions.
