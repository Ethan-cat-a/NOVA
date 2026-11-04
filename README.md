<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="112" height="112" alt="NOVA Copilot original app icon" />
  <h1>NOVA COPILOT</h1>
  <p><strong>Your AI copilot. Wherever you work.</strong></p>
  <p>A focused desktop companion for NOVA V8 — one shortcut away on Mac or Windows.</p>
  <p>
    <a href="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.3.2.dmg"><strong>Download for macOS</strong></a>
    &nbsp; · &nbsp;
    <a href="NOVA%20Copilot%20Windows/README.md"><strong>Get started on Windows</strong></a>
    &nbsp; · &nbsp;
    <a href="https://github.com/Ethan-cat-a/NOVA/releases"><strong>All releases</strong></a>
  </p>
  <p>
    <img alt="macOS" src="https://img.shields.io/badge/macOS-1.3.2-263C63?style=flat-square&logo=apple&logoColor=white" />
    <img alt="Windows" src="https://img.shields.io/badge/Windows-1.0.0-2857C5?style=flat-square&logo=windows&logoColor=white" />
    <img alt="Backend" src="https://img.shields.io/badge/AI-NOVA%20V8-526B91?style=flat-square" />
  </p>
</div>

---

## Choose your platform

<table>
  <tr>
    <td width="50%" valign="top">
      <h3> &nbsp; NOVA Copilot for macOS</h3>
      <p><strong>Version 1.3.2 · Native Swift / AppKit</strong></p>
      <p>Built for Mac with a menu-bar control, floating assistant panel and quick keyboard access.</p>
      <ul>
        <li>macOS 13 or later</li>
        <li>Apple silicon and Intel</li>
        <li>Shortcut: <code>⌘ + ⇧ + Space</code></li>
        <li>Local conversation history</li>
        <li>Daily update checks, with your approval before installation</li>
      </ul>
      <p><a href="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA-Copilot-1.3.2.dmg"><strong>↓ Download Mac DMG</strong></a></p>
      <p><sub>Users on 1.2.0, 1.3.0, or 1.3.1 must install 1.3.2 manually once; later versions can update through the in-app updater.</sub></p>
      <p><a href="NOVA%20Copilot/README.md">Mac installation guide</a> · <a href="NOVA%20Copilot.xcodeproj">Xcode project</a></p>
    </td>
    <td width="50%" valign="top">
      <h3>⊞ &nbsp; NOVA Copilot for Windows</h3>
      <p><strong>Version 1.0.0 · Python / Tkinter</strong></p>
      <p>A separate Windows edition for Lenovo ThinkPad and other Windows laptops and desktops.</p>
      <ul>
        <li>Windows 10 or Windows 11</li>
        <li>Lenovo ThinkPad and compatible PCs</li>
        <li>Shortcut: <code>Ctrl + Shift + Space</code></li>
        <li>System tray and floating panel</li>
      </ul>
      <p><a href="NOVA%20Copilot%20Windows/"> <strong>Explore Windows source</strong></a></p>
      <p><a href="NOVA%20Copilot%20Windows/README.md">Windows installation guide</a> · <a href="NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.0.0.md">Release notes</a></p>
    </td>
  </tr>
</table>

> **Important:** The Windows edition is a source distribution, not a prebuilt installer. Build it on Windows using the included `build_windows.bat` script and Python 3.10 or later. The generated `NOVA Copilot.exe` is not yet signed with a publicly trusted certificate or verified on a physical ThinkPad.

## The essentials

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>⚡ Quick access</h3>
      <p>Bring up a floating assistant with a system-wide shortcut instead of switching tabs.</p>
    </td>
    <td width="33%" valign="top">
      <h3>✦ Three work modes</h3>
      <p>Choose Fast, Hard Thinker or Coding to match the task.</p>
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
- Requests are sent to the existing `https://nova-v8.vercel.app/api/chat` endpoint.
- Conversation history is stored locally by each edition.
- Clipboard text is only read when you explicitly choose the clipboard action.

## Project layout

```text
NOVA/
├── NOVA Copilot/                  # macOS app assets, entitlements and Swift sources
├── NOVA Copilot.xcodeproj/        # macOS Xcode project
├── NOVA Copilot Windows/          # Separate Windows app and build scripts
└── README.md                      # Platform selector and project overview
```

## Releases

- [NOVA Copilot for macOS — 1.3.2](CHANGELOG.md#nova-copilot-version-132)
- [NOVA Copilot for macOS — 1.3.1](CHANGELOG.md#nova-copilot-version-131)
- [NOVA Copilot for macOS — 1.3.0](CHANGELOG.md#nova-copilot-version-130)
- [NOVA Copilot for macOS — 1.2.0](https://github.com/Ethan-cat-a/NOVA/releases/tag/v1.2.0)
- [NOVA Copilot for Windows — 1.0.0 release notes](NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.0.0.md)

---

<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="36" height="36" alt="NOVA Copilot icon" />
  <p><strong>NOVA COPILOT</strong></p>
  <sub>Made to keep NOVA within reach.</sub>
</div>
