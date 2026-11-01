# NOVA Copilot for macOS — Version 1.1.2

A native macOS desktop app with a Dock icon, a floating assistant panel, and a menu-bar control. It connects directly to the existing Nova V8 chat backend.

## Direct Nova V8 connection

The app sends chat requests to:

`https://nova-v8.vercel.app/api/chat`

It uses Nova V8's existing API contract:

- `GET /api/chat` for the backend health check.
- `POST /api/chat` with `{ "messages": [{ "role": "user" | "assistant", "content": "..." }] }`.
- The response is streamed as UTF-8 plain text, so replies appear as Nova generates them.

The app does **not** embed an OpenRouter/API key. Credentials remain on the Nova V8 Vercel server. No Nova V8 frontend deployment or environment-variable change is required by this Mac client as long as the existing V8 `/api/chat` endpoint remains enabled.

## Features

- Native floating panel positioned near the right edge of the screen.
- Dock app icon, high-contrast sparkle menu-bar button, and global shortcut `⌘⇧Space` to show/hide the panel.
- Clicking the Dock icon or choosing **Show NOVA Copilot** reopens a hidden panel.
- Fast, Hard Thinker, and Coding response modes.
- Streaming replies and stop/cancel support.
- Local chat history stored on this Mac (up to 40 recent conversations).
- Recent-chat switching and new-chat action.
- Optional keep-on-top and Launch at Login settings.
- Manual clipboard-context insertion. The app only reads clipboard text when you press the paperclip or the clipboard starter; it does not monitor the clipboard.
- Custom NOVA Copilot macOS app icon and matching in-app brand logo.

## Install the shareable build

Extract `NOVA-Copilot-macOS-1.1.2.zip`, then move **NOVA Copilot 1.1.2.app** into **Applications**. The app requires macOS 13 or later and an internet connection to reach Nova V8.

This build uses an ad hoc local signature; it is not signed with a Developer ID certificate or notarized. macOS may ask you to confirm the first launch. Only open it if you trust the person who shared it. A Developer ID signature and Apple notarization are needed for a no-warning download experience.

## Prepare a no-warning release

The Release configuration enables the hardened runtime required for notarization. To distribute an app that Gatekeeper opens without the first-open warning, the app still needs a Developer ID Application signature and Apple notarization. These require an active Apple Developer Program membership and a Developer ID certificate available in the signing Mac's Keychain. No certificate is currently installed on the build Mac.

After the certificate is installed, open the project in Xcode, choose **Product > Archive**, then use Organizer's **Distribute App > Developer ID > Upload** flow to sign and submit the archive for notarization. Export the accepted, notarized app for sharing.

The app does not include an API key; chat requests go to the existing Nova V8 server.

## Build in Xcode

1. Extract the ZIP.
2. Open `NOVA Copilot.xcodeproj` in Xcode.
3. Select the **NOVA Copilot** scheme and **My Mac** as the destination.
4. In **Signing & Capabilities**, select your Personal Team for local builds. Public distribution needs an Apple Developer Program team and a Developer ID Application certificate.
5. Press `⌘B` to build, then `⌘R` to run.
6. NOVA Copilot appears in the Dock and menu bar. Press `⌘⇧Space` from another app to show or hide the floating panel.

The project targets macOS 13 or later. Xcode can build a local `.app` for your Mac; distributing it without Gatekeeper warnings requires Developer ID signing and notarization.

## Connection check

On launch, the status line checks Nova V8's `/api/chat` health endpoint. A green dot and `Nova V8 connected` indicate the backend health check passed. If it shows `Connection unavailable`, check that `https://nova-v8.vercel.app/api/chat` is deployed and reachable from your Mac. The first live chat also verifies the POST/streaming path.

## Privacy and storage

- API credentials remain server-side on Nova V8.
- Conversation history is saved locally through macOS `UserDefaults` under the existing NOVA Companion history key for compatibility with that earlier build.
- The app requests network-client permission only; it does not request full disk access, screen recording, accessibility control, or automatic clipboard monitoring.
