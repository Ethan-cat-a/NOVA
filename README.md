<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="112" height="112" alt="NOVA Copilot original app icon" />
  <h1>NOVA COPILOT</h1>
  <p><strong>Your AI copilot. Wherever you work.</strong></p>
  <p>A focused desktop companion for NOVA V8 — one shortcut away on Mac or Windows.</p>
  <p><strong>Mac source version 1.6.5</strong> adds a guarded Agent mode with calculator and selected-document search tools.</p>
  <p>
    <a href="https://github.com/Ethan-cat-a/NOVA/releases/download/v1.6.5/NOVA-Copilot-1.6.5.dmg"><strong>Download latest macOS app · 1.6.5 DMG</strong></a>
    &nbsp; · &nbsp;
    <a href="https://github.com/Ethan-cat-a/NOVA/releases/download/windows-v1.5.3/NOVA-Copilot-Windows-1.5.3.exe"><strong>Download Windows app · 1.5.3</strong></a>
    &nbsp; · &nbsp;
    <a href="https://github.com/Ethan-cat-a/NOVA/releases"><strong>All releases</strong></a>
  </p>
  <p>
    <img alt="macOS source" src="https://img.shields.io/badge/macOS%20source-1.6.5-263C63?style=flat-square&logo=apple&logoColor=white" />
    <img alt="Windows" src="https://img.shields.io/badge/Windows-1.5.3-2857C5?style=flat-square&logo=windows&logoColor=white" />
    <img alt="Backend" src="https://img.shields.io/badge/AI-NOVA%20V8-526B91?style=flat-square" />
  </p>
</div>

---

## Choose your platform

<table>
  <tr>
    <td width="50%" valign="top">
      <h3> &nbsp; NOVA Copilot for macOS</h3>
      <p><strong>Source version 1.6.5 · Native Swift / AppKit</strong></p>
      <p>Built for Mac with a menu-bar control, floating assistant panel and quick keyboard access.</p>
      <ul>
        <li>Chat as a guest with optional Google or email/password sign-in</li>
        <li>25 messages per UTC day; one-time owner code for the private unlimited profile</li>
        <li>macOS 13 or later</li>
        <li>Apple silicon and Intel</li>
        <li>Shortcut: <code>⌘ + ⇧ + Space</code></li>
        <li>Local conversation history</li>
        <li>Search saved chats, rename conversations and delete old ones</li>
        <li>Readable formatted answers with hover-to-copy code blocks</li>
        <li>Daily and manual update checks with version details and release notes before approval</li>
        <li>One-click summarize and rewrite actions for copied text</li>
        <li>Review extracted text from up to five context items total: images, PDFs, Word documents or screen captures</li>
        <li>Collapsed source details show attached filenames and PDF pages under relevant replies</li>
        <li>Optionally search PDFs, Word, RTF, Markdown and text files in folders you choose, one message at a time</li>
        <li>Document search runs locally; at most four relevant excerpts are sent only when you enable it</li>
        <li>Word Doc mode formats headings, lists, bold and italics in new .docx files</li>
        <li>Agent mode calculates and searches only text from files attached or selected for that chat; it cannot change files or run commands</li>
        <li>Answer actions appear on hover, with Copy, Try again and Word export</li>
        <li>Matches the Mac’s light or dark appearance</li>
      </ul>
      <p><a href="https://github.com/Ethan-cat-a/NOVA/releases/download/v1.6.5/NOVA-Copilot-1.6.5.dmg"><strong>↓ Latest Mac release · 1.6.5 DMG</strong></a> · <a href="https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.6.5">Release notes</a></p>
      <p><sub>Users on 1.2.0, 1.3.0, or 1.3.1 must install 1.3.2 manually once; users on 1.3.2 can update through the in-app updater.</sub></p>
      <p><a href="NOVA%20Copilot/README.md">Mac installation guide</a> · <a href="NOVA%20Copilot.xcodeproj">Xcode project</a></p>
    </td>
    <td width="50%" valign="top">
      <h3>⊞ &nbsp; NOVA Copilot for Windows</h3>
      <p><strong>Source version 1.5.3 · Python / Tkinter</strong></p>
      <p>A standalone Windows edition for Windows 10 and 11 PCs.</p>
      <ul>
        <li>Chat as a guest with optional Google or email/password sign-in</li>
        <li>25 messages per UTC day; one-time owner code for the private unlimited profile</li>
        <li>Windows 10 or Windows 11</li>
        <li>Shortcut: <code>Ctrl + Shift + Space</code></li>
        <li>System tray and floating panel</li>
        <li>Word Doc mode, editable document drafts and reviewed PDF text</li>
        <li>Copy, Try again and a manual update check</li>
      </ul>
      <p><a href="https://github.com/Ethan-cat-a/NOVA/releases/download/windows-v1.5.3/NOVA-Copilot-Windows-1.5.3.exe"><strong>↓ Download Windows app · 1.5.3 EXE</strong></a></p>
      <p><a href="NOVA%20Copilot%20Windows/README.md">Windows installation guide</a> · <a href="NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.5.3.md">Release notes</a> · <a href="NOVA%20Copilot%20Windows/">Source</a></p>
    </td>
  </tr>
</table>

> Version 1.6.5 is the latest macOS release. Version 1.5.3 is the latest Windows release.

> **Mac install:** Open the downloaded DMG and drag **NOVA Copilot.app** onto the **Applications** shortcut. This build is not signed with an Apple Developer ID; macOS may ask you to approve it under **System Settings → Privacy & Security** the first time.

> **Windows install:** Download and open the Windows 1.5.3 EXE above; no ZIP extraction or Python install is needed. The app is unsigned, so Windows SmartScreen may show a warning. GitHub Actions builds it on a Windows runner.

## The essentials

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>⚡ Quick access</h3>
      <p>Bring up a floating assistant with a system-wide shortcut instead of switching tabs.</p>
    </td>
    <td width="33%" valign="top">
      <h3>✦ Five work modes</h3>
      <p>Choose Fast, Hard Thinker, Coding, Word Doc or Agent to match the task.</p>
    </td>
    <td width="33%" valign="top">
      <h3>↗ Live responses</h3>
      <p>See Nova's reply stream into the conversation as it is generated.</p>
    </td>
  </tr>
  <tr>
    <td width="33%" valign="top">
      <h3>▤ Chat history</h3>
      <p>Return to recent conversations saved locally on your device.</p>
    </td>
    <td width="33%" valign="top">
      <h3>⌘ Clipboard on request</h3>
      <p>Insert copied text when you choose. The apps do not continuously monitor clipboard contents.</p>
    </td>
    <td width="33%" valign="top">
      <h3>◈ One AI backend</h3>
      <p>Both desktop editions connect to the existing NOVA V8 chat service.</p>
    </td>
  </tr>
</table>

## Separate apps. One NOVA identity.

The Mac and Windows editions share the same product identity and NOVA V8 service, but they are independent desktop applications with separate interfaces and build processes.

| | macOS edition | Windows edition |
|---|---|---|
| Application technology | Swift / AppKit | Python / Tkinter |
| Build environment | Xcode on Mac | Python and PyInstaller on Windows |
| Local chat storage | Mac device | Windows device |
| Install guide | [Read guide](NOVA%20Copilot/README.md) | [Read guide](NOVA%20Copilot%20Windows/README.md) |

## Privacy and connection

- No NOVA V8 API key is embedded in either desktop client.
- Chat requests go through the authenticated `https://nova-copilot-gateway.vercel.app/api/chat` service.
- Conversation history is stored locally by each edition.
- Clipboard text is only read when you explicitly choose the clipboard action.
- The Mac edition can review extracted text from images, PDFs and Word documents before sending it. The Windows edition supports `.docx` and PDFs with selectable text; scanned-document OCR and image import are currently Mac-only.
- Screen/window capture uses the macOS 14 or later picker; importing images and PDFs works on macOS 13 or later.
- Word Doc mode saves generated text as a new `.docx`; formatting, tables and images from an imported file are not preserved.

## Google sign-in setup

The desktop clients can sign in with Google through Supabase Auth, avoiding confirmation emails for Google accounts. Project owners must configure a Google OAuth client and the app callback URLs once; see [Google sign-in setup](GOOGLE_SIGN_IN_SETUP.md). Keep the Google client secret in Supabase and out of the app and source repository.

## Project layout

```text
NOVA/
├── NOVA Copilot/                  # macOS app assets, entitlements and Swift sources
├── NOVA Copilot.xcodeproj/        # macOS Xcode project
├── NOVA Copilot Windows/          # Separate Windows app and build scripts
└── README.md                      # Platform selector and project overview
```

## Releases

- [NOVA Copilot for Windows — 1.5.3](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.5.3)
- [NOVA Copilot for macOS — 1.6.5](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.6.5)
- [NOVA Copilot for macOS — 1.6.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.6.0)
- [NOVA Copilot for macOS — 1.5.6](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.5.6)
- [NOVA Copilot for macOS — 1.5.2](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.5.2)
- [NOVA Copilot for Windows — 1.5.2](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.5.2)
- [NOVA Copilot for macOS — 1.5.1](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.5.1)
- [NOVA Copilot for macOS — 1.5.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.5.0)
- [NOVA Copilot for Windows — 1.5.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.5.0)
- [NOVA Copilot for macOS — 1.4.7](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.4.7)
- [NOVA Copilot for macOS — 1.4.2](CHANGELOG.md#nova-copilot-version-142-2026-11-05)
- [NOVA Copilot for Windows — 1.4.2](CHANGELOG.md#nova-copilot-for-windows-version-142-2026-11-05)
- [NOVA Copilot for macOS — 1.4.1](CHANGELOG.md#nova-copilot-version-141-2026-11-05)
- [NOVA Copilot for macOS — 1.4.0](CHANGELOG.md#nova-copilot-version-140-2026-11-05)
- [NOVA Copilot for macOS — 1.3.5](CHANGELOG.md#nova-copilot-version-135-2026-11-05)
- [NOVA Copilot for macOS — 1.3.3](CHANGELOG.md#nova-copilot-version-133)
- [NOVA Copilot for macOS — 1.3.2](CHANGELOG.md#nova-copilot-version-132)
- [NOVA Copilot for macOS — 1.3.1](CHANGELOG.md#nova-copilot-version-131)
- [NOVA Copilot for macOS — 1.3.0](CHANGELOG.md#nova-copilot-version-130)
- [NOVA Copilot for macOS — 1.2.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.2.0)
- [NOVA Copilot for Windows — 1.4.2](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.4.2)
- [NOVA Copilot for Windows — 1.1.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/windows-v1.1.0)
- [NOVA Copilot for Windows — 1.4.2 release notes](NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.4.2.md)
- [NOVA Copilot for Windows — 1.1.0 release notes](NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.1.0.md)
- [NOVA Copilot for Windows — 1.0.0 release notes](NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.0.0.md)

---

<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="36" height="36" alt="NOVA Copilot icon" />
  <p><strong>NOVA COPILOT</strong></p>
  <sub>Made to keep NOVA within reach.</sub>
</div>
