<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot original app icon" />
  <h1>NOVA Copilot for macOS</h1>
  <p><strong>Your AI copilot. One shortcut away.</strong></p>
  <p><img alt="macOS version" src="https://img.shields.io/badge/macOS-1.4.1-263C63?style=flat-square&logo=apple&logoColor=white" /> <img alt="macOS 13+" src="https://img.shields.io/badge/platform-macOS%2013%2B-526B91?style=flat-square" /></p>
  <p>Released November 5, 2026.</p>
  <p><a href="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.4.1.zip"><strong>↓ Download latest release for Mac · 1.4.1</strong></a></p>
</div>

---

## Built for your Mac

A native Swift / AppKit assistant that brings NOVA V8 into a lightweight floating panel. Open it from the menu bar or with **⌘ + ⇧ + Space** without losing your place.

## Features

| **Stay in your flow** | **Choose how to think** | **Keep control** |
| --- | --- | --- |
| Menu-bar access, a floating panel, animated right-edge launcher and manual update button. | Fast, Hard Thinker and Coding modes, plus one-click summary and rewrite actions for copied text. | Review text extracted from screenshots, images or PDFs before sending it to NOVA. |

- Streaming responses as Nova generates them.
- Recent conversations to pick up where you left off.
- Optional Launch at Login and Keep on Top.
- Image and PDF OCR runs locally. NOVA receives only the text you approve, not the original file.
- Screen and window capture uses the macOS 14+ system picker; image and PDF import works on macOS 13+.
- Import `.docx` or `.doc` files for text context. Choose **Word Doc** mode to create a document or fill an imported one, then review, edit and save the result as `.docx`.
- When adding a new document in Word Doc mode, include the details to fill in your current message; earlier chat drafts are not included.
- Saved Word documents contain text. Formatting, tables and images from an imported document are not retained. Word Doc mode accepts up to 15,000 characters of imported context.

## Install

1. [Download the Mac app ZIP](https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.4.1.zip).
2. Double-click the ZIP to expand it, then drag **NOVA Copilot.app** to **Applications**.
3. Launch NOVA Copilot from Applications.

Requires **macOS 13 or later**. The universal build supports Apple silicon and Intel Macs.

> **Upgrade:** Users on 1.2.0, 1.3.0 or 1.3.1 need to install 1.3.2 manually once. Users on 1.3.2 and later can update through Sparkle after approving it.

> **First launch:** This build is not notarized. If macOS blocks it, Control-click **NOVA Copilot.app** in Applications, choose **Open**, then confirm **Open**. Only install apps from a source you trust.

## Privacy

- The app contains no API key; chat requests go to the existing NOVA V8 server.
- Chat history stays on your Mac.
- Clipboard text is read only when you choose the clipboard action; the app does not monitor it.

## Build from source

1. Open `NOVA Copilot.xcodeproj` in Xcode.
2. Select the **NOVA Copilot** scheme and **My Mac** as the destination.
3. Choose a signing team under **Signing & Capabilities**, then build with **⌘B** or run with **⌘R**.

Backend: `https://nova-v8.vercel.app/api/chat`

---

Looking for the Windows edition? See [NOVA Copilot for Windows](../NOVA%20Copilot%20Windows/README.md).
