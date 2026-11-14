<div align="center">
  <img src="https://raw.githubusercontent.com/Ethan-cat-a/NOVA/main/NOVA%20Copilot/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="88" height="88" alt="NOVA Copilot original app icon" />
  <h1>NOVA Copilot for macOS</h1>
  <p><strong>Your AI copilot. One shortcut away.</strong></p>
  <p><img alt="macOS source" src="https://img.shields.io/badge/source-1.7.1-263C63?style=flat-square&logo=apple&logoColor=white" /> <img alt="macOS 13+" src="https://img.shields.io/badge/platform-macOS%2013%2B-526B91?style=flat-square" /></p>
  <p>Version 1.7.1 fixes the side launcher so the avatar stays visible when collapsed and the drag grip remains on-screen when expanded.</p>
  <p><a href="https://github.com/Ethan-cat-a/NOVA/releases/download/v1.7.1/NOVA-Copilot-1.7.1.dmg"><strong>↓ Latest published Mac app · 1.7.1 DMG</strong></a></p>
</div>

---

## Built for your Mac

A native Swift / AppKit assistant that brings NOVA V8 into a lightweight floating panel. Open it from the menu bar or with **⌘ + ⇧ + Space** without losing your place.

## Features

| **Stay in your flow** | **Choose how to think** | **Keep control** |
| --- | --- | --- |
| Avatar eyes in the menu bar, a floating panel and a draggable right-edge launcher that expands on hover. | Fast, Hard Thinker and one CS Agent mode for coding, Word documents and plugins. | Review text extracted from screenshots, images, PDFs, code projects or a selected Chrome page before sending it to NOVA. |

- Streaming responses stay in view while you’re at the bottom; use **Latest** to return after scrolling up.
- Retry a failed reply without losing the next message draft you’re writing.
- Copy confirmations are brief, so they don’t crowd the panel.
- Recent conversations to pick up where you left off.
- Search local conversation titles and messages, rename useful chats, and delete old ones.
- Completed answers format headings, lists, quotes and code blocks; hover over a code block to copy it.
- Optional Launch at Login and Keep on Top.
- Text extraction for up to five context items total—images, PDFs, Word documents or screen captures—runs locally. Review each item before sending; NOVA receives only the text you approve, not the original files.
- Completed replies to file-based questions can show a collapsed source-details row with the supplied filenames and PDF pages; NOVA is asked to cite only details present in the extracted text.
- Add folders once, then enable **My Documents** for a single request. NOVA searches PDFs, Word, RTF, Markdown, text and common source-code files locally and sends at most four relevant excerpts only for that request.
- CS Agent combines coding help, Word document creation/filling and Agent tools. Existing chats in Coding, Word Doc and Agent modes migrate to CS Agent.
- **Git status** can include a read-only summary for a selected repository when you opt in for a message. No file contents are read by Git; My Documents search remains a separate opt-in.
- **Google Chrome** can open a Google Search for your question or share the current page after macOS access is allowed. NOVA extracts the page text locally and shows a preview; only the reviewed text is sent when you submit your message.
- The CS Agent apps menu opens a selected project in Xcode or Microsoft Word. Allowlisted server plugins provide calculator, selected-document search and read-only public GitHub lookups. NOVA does not edit files, run arbitrary commands, commit/push changes or install third-party plugins.
- CS Agent can search public GitHub repositories and read public files, issues and pull requests. Access is read-only and does not reach private repositories.
- Google Search remains a free, explicit handoff to Chrome; NOVA does not invoke a paid hosted web-search service.
- CS Agent text now streams as the gateway receives it. Batched display updates, periodic history saves and live system-colored text reduce typing lag, scrolling churn and the brief white-text flash.
- Without the per-message **My Documents** option, no text from the saved folders is sent. Document contents are not added to saved chat history.
- Screen and window capture uses the macOS 14+ system picker; image and PDF import works on macOS 13+.
- Import `.docx` or `.doc` files for text context. In CS Agent, choose **Make next reply a Word file** to create or fill a document, then review, edit and save the result as `.docx`.
- New Word exports format headings, lists, bold, italics and code blocks. Existing page layouts, tables and images are not retained. One Word source and up to four reference files can be used per request.
- Completed-answer actions appear on hover; Copy remains available to assistive technologies.
- The panel follows macOS light and dark appearance.
- Guest and regular profiles receive 25 chat requests per UTC day, enforced by the server. A one-time owner code can activate the private unlimited-use profile.
- Guest usage is attached to a device profile. Clearing NOVA’s saved app data can create a new profile and allowance.

## Install

1. [Download the latest Mac app DMG (1.7.1)](https://github.com/Ethan-cat-a/NOVA/releases/download/v1.7.1/NOVA-Copilot-1.7.1.dmg).
2. Open the downloaded disk image and drag **NOVA Copilot.app** onto the **Applications** shortcut.
3. Eject the disk image, then launch NOVA Copilot from Applications.

Requires **macOS 13 or later**. The universal build supports Apple silicon and Intel Macs.

> **Upgrade:** Users on 1.2.0, 1.3.0 or 1.3.1 need to install 1.3.2 manually once. Users on 1.6.7 or 1.6.8 should install the 1.7.1 DMG manually once; their updater cannot install the Sparkle fix. Users on 1.6.9 and later can use the in-app updater.

> **First launch:** This build is not signed with an Apple Developer ID or notarized. If macOS blocks it, Control-click **NOVA Copilot.app** in Applications, choose **Open**, then confirm **Open**. Only install apps from a source you trust.

## Privacy

- No NOVA/OpenRouter model key is embedded; chat requests go to the NOVA Copilot gateway, which verifies the account and routes the selected mode to its configured model.
- The Supabase publishable key is used only for account authentication; the access and refresh tokens are stored in macOS Keychain.
- Chat history stays on your Mac.
- The document library stores folder access bookmarks on your Mac. Searching and text extraction run locally; only opted-in excerpts are included in that message to NOVA.
- Git summaries are read-only and included only when selected for a single message. Chrome page text is extracted only after you choose to share the active tab and review its preview.
- Clipboard text is read only when you choose the clipboard action; the app does not monitor it.

Google sign-in uses Supabase Auth and a system browser. The first project setup requires Google OAuth credentials and the app callback URL in Supabase; see the [setup guide](../GOOGLE_SIGN_IN_SETUP.md). The Google client secret stays in Supabase and is never included in the app.

## Build from source

1. Open `NOVA Copilot.xcodeproj` in Xcode.
2. Select the **NOVA Copilot** scheme and **My Mac** as the destination.
3. Choose a signing team under **Signing & Capabilities**, then build with **⌘B** or run with **⌘R**.

To create the ad-hoc signed release package, run `scripts/package-macos-release.sh <output-directory>`. It deliberately leaves the app outside Hardened Runtime library validation because this distribution has no Developer ID Team ID; Sparkle's nested helpers keep their own signatures.

Backend: `https://nova-copilot-gateway.vercel.app/api/chat`

---

Looking for the Windows edition? See [NOVA Copilot for Windows](../NOVA%20Copilot%20Windows/README.md).
