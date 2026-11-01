<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="112" alt="NOVA Copilot app icon" />
  <h1>NOVA Copilot</h1>
  <p><strong>Your AI copilot, one shortcut away.</strong></p>
  <p>A native macOS assistant that keeps Nova close—from the menu bar or with ⌘⇧Space.</p>
  <p>
    <a href="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.1.2.dmg"><strong>↓ Download for Mac · DMG</strong></a>
    &nbsp; · &nbsp;
    <a href="https://github.com/Ethan-cat-a/NOVA/releases">All releases</a>
    &nbsp; · &nbsp;
    <a href="#features">Explore features</a>
  </p>
  <p><sub>macOS 13+ &nbsp;·&nbsp; Apple silicon and Intel &nbsp;·&nbsp; Version 1.1.2</sub></p>
</div>

---

## ✨ Nova, right where you need it

NOVA Copilot brings the Nova assistant into a lightweight Mac app. Pop open a floating panel, ask a question, and get a streamed reply without losing your place.

## Features

| **Stay in your flow** | **Choose how to think** | **Keep control** |
| --- | --- | --- |
| Open from the menu bar or press **⌘⇧Space**. Keep the panel close while you work. | Switch between **Fast**, **Hard Thinker**, and **Coding** modes. | Stop a reply, keep local chat history, and choose when clipboard text is added. |

- **Streaming responses** appear as Nova generates them.
- **Recent chats** make it easy to pick up where you left off.
- **Launch at Login** and **Keep on Top** are optional.

## Install in a minute

1. [Download the Mac installer](https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.1.2.dmg).
2. Open the DMG and drag **NOVA Copilot.app** to **Applications**.
3. Launch it from Applications.

Requires **macOS 13 or later** and an internet connection. The universal build supports Apple silicon and Intel Macs.

> **First launch:** This build is not signed with a Developer ID certificate or notarized. If macOS blocks it, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. Only install apps from people you trust.

## Privacy, by design

- The app contains **no API key**; chat requests go to the existing Nova V8 server.
- Chat history stays on your Mac.
- Clipboard text is read only when you choose the clipboard action; the app does not monitor it.

<details>
<summary><strong>For developers</strong></summary>

### Build from source

1. Open `NOVA Copilot.xcodeproj` in Xcode.
2. Select the **NOVA Copilot** scheme and **My Mac** as the destination.
3. Choose a signing team under **Signing & Capabilities**, then build with **⌘B** or run with **⌘R**.

### Backend

The app connects to `https://nova-v8.vercel.app/api/chat` using Nova V8's existing chat endpoint. No frontend or server configuration change is required for this client.

</details>

---

<div align="center">
  <sub>Made for macOS. Built to keep Nova within reach. ✦</sub>
</div>
