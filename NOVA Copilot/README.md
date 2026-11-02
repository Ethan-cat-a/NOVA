# NOVA Copilot for macOS

**Version 1.2.0 · macOS 13+ · Apple silicon and Intel**

NOVA Copilot for macOS is the native Swift / AppKit edition. This guide covers only the Mac app. The Windows edition has its own separate folder and guide.

## Download

[Download NOVA Copilot 1.2.0 for Mac (.dmg)](https://github.com/Ethan-cat-a/NOVA/releases/download/v1.2.0/NOVA-Copilot-1.2.0.dmg)

## Features

- Menu-bar access and global shortcut **⌘⇧Space**.
- Floating assistant panel with an animated right-edge launcher.
- Fast, Hard Thinker, and Coding modes.
- Streaming replies through Nova V8.
- Recent chats stored locally on this Mac.
- Explicit clipboard text insertion.
- Keep on Top and optional Launch at Login.

## Install

1. Download and open the DMG.
2. Drag **NOVA Copilot.app** into **Applications**.
3. Launch NOVA Copilot from Applications.

Requires macOS 13 or later and an internet connection.

> **First launch:** This build is not notarized. If macOS blocks it, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. Only install apps from a source you trust.

## Privacy

- The app contains no API key; chat requests go to the existing Nova V8 server.
- Chat history stays on your Mac.
- Clipboard text is read only when you choose the clipboard action; the app does not monitor it.

## Build from source

1. Open `NOVA Copilot.xcodeproj` in Xcode.
2. Select the **NOVA Copilot** scheme and **My Mac** as the destination.
3. Choose a signing team under **Signing & Capabilities**, then build with **⌘B** or run with **⌘R**.

The app connects to `https://nova-v8.vercel.app/api/chat`.

---

Need the Windows edition? See [NOVA Copilot for Windows](../NOVA%20Copilot%20Windows/README.md).
