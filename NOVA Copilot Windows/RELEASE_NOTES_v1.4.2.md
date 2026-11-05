# NOVA Copilot for Windows 1.4.2

**Release channel:** Windows  
**Target systems:** Windows 10 and Windows 11

## What’s new

- Catches the Windows edition up to the NOVA 1.4.2 feature line with an explicit Windows version and downloadable release.
- Shows thinking and writing status while a response streams, and labels the active control **Stop**.
- Adds **Copy** and **Try again** actions to completed replies. Retries retain the request’s original mode and attached document text.
- Adds **Word Doc** mode to create a document draft or fill an attached `.docx`, then review, edit and save the result as a new `.docx`.
- Adds reviewed text import for Word files and selectable-text PDFs, with a 15,000-character context limit.
- Adds previewed one-click summarize and rewrite actions for copied text.
- Adds a visible manual update check. It checks GitHub and opens a newer release page after the user approves; installing the downloaded update remains manual.
- Preserves immediate Stop behavior and in-place streaming updates from Windows 1.1.0.

## Windows-specific limits

- `.docx` and text-based PDF content are supported. Legacy `.doc` files, scanned PDF OCR, image OCR and screen/window capture are not included in this Windows build.
- Word export creates a new text-based `.docx`. It does not retain formatting, tables or images from an attached source document.
- The application is unsigned, so Windows SmartScreen may display a warning.

## Install

Download `NOVA-Copilot-Windows-1.4.2.zip` from the [Windows 1.4.2 release](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.4.2), extract the ZIP and open `NOVA Copilot.exe`. Python is not required.

## Validation

- GitHub Actions builds the executable on a Windows runner and runs the existing Windows app checks.
- The package contains the self-contained executable and a short installation note.
