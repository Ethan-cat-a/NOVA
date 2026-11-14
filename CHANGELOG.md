# NOVA Copilot for macOS Version 1.6.5 (2026-11-14)

- Adds an opt-in Agent mode powered by Nemotron 3 Ultra with a bounded OpenRouter tool-call loop.
- Adds a modular server-side plugin registry with calculator and selected-document search tools; it cannot access unselected files, modify files, run shell commands or control other apps.
- Limits each agent reply to two tool rounds and four executed tool calls, and keeps generated reasoning out of the visible response.
- Routes Hard Thinker to NVIDIA Nemotron 3 Ultra and improves 429 messages to distinguish provider capacity from OpenRouter rate limits where metadata is available.
- Bumps the Mac marketing version to 1.6.5 and build number to 25.

# NOVA Copilot for macOS Version 1.6.0 (2026-11-10)

- Adds an optional My Documents library: choose folders once, then explicitly enable a one-message search when you want NOVA to use them.
- Searches PDFs, Word documents, RTF, Markdown and plain-text files locally, ranks matches against the question, and sends at most four short excerpts only for that opted-in request.
- Keeps document text out of saved chat history; replies show the existing collapsed source-details disclosure for the files used.
- Adds persistent, user-selected folder bookmarks for the macOS app sandbox.
- Bumps the Mac marketing version to 1.6.0 and build number to 24.

# NOVA Copilot for macOS Version 1.5.6 (2026-11-10)

- Adds a collapsed source-details disclosure under replies to requests with attached files, showing their exact filenames and PDF pages included in the extracted text.
- Asks NOVA to cite only filenames and PDF page labels present in the supplied material; it does not invent external citations.
- Bumps the Mac marketing version to 1.5.6 and build number to 23.

# NOVA Copilot for macOS Version 1.5.5 (2026-11-09)

- Reuses one long-lived URLSession connection pool for Mac chat and Supabase account traffic, and records privacy-safe DNS, TCP, TLS and first-byte timings.
- Keeps HTTPS sockets and TLS sessions pooled for Supabase and the NOVA V8 upstream on warm gateway instances; enables Vercel Fluid Compute and reports gateway stage timings.
- Bumps the Mac marketing version to 1.5.5 and build number to 22.

# NOVA Copilot for macOS Version 1.5.4 (2026-11-07)

- Fixes owner-code entry with a visible **Paste** button that reads clipboard text directly while keeping the code masked.
- Fixes the production gateway's `/api/chat` route by deploying from the `nova-copilot-gateway` project directory.
- Bumps the Mac marketing version to 1.5.4 and build number to 21.

# NOVA Copilot Version 1.5.2 (2026-11-07)

- Makes account sign-in optional. Chat starts a Supabase guest profile automatically; existing Google and email/password sign-in remain available.
- Enforces 25 chat requests per UTC day and 10 per minute for guest and regular profiles. The owner profile keeps unlimited daily use with a 30-per-minute cap.
- Adds a one-time owner access code that attaches unlimited owner status to the current NOVA profile without placing the code in the public app source.
- Bumps the Mac build number to 20 and both clients to version 1.5.2.
- Guest allowances are associated with a device profile. Clearing saved app data can create a new profile and a new allowance.

# NOVA Copilot Version 1.5.1 (2026-11-06)

- Removes self-service email/password account creation from the Mac and Windows clients. Email/password remains available for existing accounts.
- Keeps Google sign-in as the simple path to an existing account, including the precreated owner account when the verified Google email matches.
- Bumps the Mac build number to 19 and both clients to version 1.5.1.
- No shared owner login code is embedded in the public app; the owner account remains protected by Google authentication or its existing password.

# NOVA Copilot Version 1.5.0 (2026-11-06)

- Adds email/password account creation and sign-in. Chat requires a verified email address.
- Stores Mac sessions in Keychain and Windows sessions with Windows DPAPI encryption.
- Enforces chat limits server-side: 25 messages per UTC day and 10 per minute for regular accounts; the designated verified owner account has unlimited daily use and a 30-per-minute burst cap.
- Adds a separate streaming gateway that checks the Supabase account and quota, then forwards the existing NOVA V8 response unchanged.
- Email confirmation and Supabase Auth rate protections reduce sign-up abuse. Cloudflare Turnstile is not configured; it needs site and secret keys. General sign-ups also need a custom SMTP sender before launch because Supabase’s built-in sender is restricted.
- The production gateway is deployed. Existing older app versions continue using the legacy endpoint until the authenticated clients are distributed.

# NOVA Copilot Version 1.4.8 (2026-11-06)

- Keeps new replies in view while you’re at the bottom and adds a **Latest** button after you scroll up.
- Preserves the next message draft when retrying a failed or regenerated response.
- Shows a brief **Copied** confirmation after copying an answer or code block.
- Keeps the NOVA Copilot name on two lines in the compact panel header.

# NOVA Copilot Version 1.4.7 (2026-11-06)

- Lightens the conversation canvas so it matches the normal panel background around messages.

# NOVA Copilot for Windows Version 1.4.2 (2026-11-05)

- Updates the Windows edition to the current 1.4.2 feature line.
- Adds visible thinking/writing status, a labeled Stop control, Copy and Try again for responses.
- Adds Word Doc mode with `.docx` import, editable draft review and `.docx` export.
- Adds reviewed text import for Word files and selectable-text PDFs, plus previewed summarize/rewrite clipboard actions.
- Adds a manual GitHub update check and keeps the immediate Stop and in-place streaming fixes.
- Documents Windows-specific limits: scanned PDF/image OCR and screen capture are not included; `.docx` export is text-based.

# NOVA Copilot for Windows Version 1.1.0 (2026-11-05)

- Adds a self-contained Windows release package built for download.
- Makes Stop release the UI immediately while a cancelled connection finishes winding down.
- Updates streamed responses in place, preserving scroll position and avoiding full conversation redraws.
- Adds cancellation, UTF-8 streaming and incremental-rendering tests.

# NOVA Copilot Version 1.4.6 (2026-11-05)

- Formats completed answers with readable headings, lists, quotes and code blocks while keeping live streaming responsive.
- Adds hover-to-copy controls to individual code blocks.
- Adds local chat-history search across conversation titles and messages, with rename and confirmed delete actions.

# NOVA Copilot Version 1.4.5 (2026-11-05)

- Lets you add up to five context items total—images, PDFs, Word documents or screen captures—review each extracted text preview locally, and remove individual items before sending.
- Formats new Word exports with headings, bulleted and numbered lists, bold, italics and code blocks; original Word layouts, tables and images are not preserved.
- Follows the Mac’s light or dark appearance.
- Hides reply actions until you hover over a completed answer, while keeping Copy available as an accessibility action.

# NOVA Copilot Version 1.4.2 (2026-11-05)

- Shows a clear thinking or writing indicator while NOVA streams a response, with a labeled Stop button.
- Adds Copy to completed replies and Try again to the latest reply.
- Regenerates the latest reply in the same mode and with its original document context when applicable.

# NOVA Copilot Version 1.4.1 (2026-11-05)

- Adds **Word Doc** mode to create a document from a request or fill an attached Word document.
- Reads `.docx` and `.doc` files as text on the Mac, with a preview before sending their contents to NOVA.
- Lets you review and edit completed drafts, then save them as `.docx` files using the macOS save dialog.
- Uses the current request with each newly attached Word document so earlier drafts do not get mixed in.
- Exports text rather than the original document's formatting, tables or images; documents above the context limit cannot be filled in this mode.

# NOVA Copilot Version 1.4.0 (2026-11-05)

- Adds a context menu for importing images and PDFs, capturing a screen or window on macOS 14+, and adding copied text.
- Extracts readable text from images, PDFs and captures locally with Apple Vision; review it before sending it with a question.
- Keeps the original image or PDF on the Mac. NOVA V8 receives only the approved extracted text, with a 15,000-character limit.
- Adds PDF page limits and import size limits to keep context capture responsive.
- Keeps the newest response in view as its streamed text arrives.

# NOVA Copilot Version 1.3.5 (2026-11-05)

- Shows the installed version when NOVA is up to date and both installed and available versions when an update is found.
- Adds a compact **What’s New** view with release notes from the signed Sparkle feed before installing an update.

# NOVA Copilot Version 1.3.4 (2026-11-05)

- Remembers the selected rewrite tone and adds a dismissible first-run tip.
- Adds Preferences for Launch at Login, automatic update checks, check frequency, and the keyboard shortcut.
- Shows manual update check results in the panel and makes failed connection requests retryable.

# NOVA Copilot Version 1.3.3

- Adds one-click clipboard actions to summarize or rewrite copied text.
- Keeps quick actions explicit: text is read from the clipboard only when an action is selected, and NOVA starts a separate chat when needed.
- Adds a panel-header button for checking Sparkle updates immediately.

# NOVA Copilot Version 1.3.2

- Fixes launch failure by embedding the correct Frameworks runtime search path for Sparkle.
- Disables Hardened Runtime library validation so the app can load the embedded ad-hoc-signed Sparkle framework when distributed without an Apple Developer ID.
- Increments the marketing version to 1.3.2 and build number to 6.
- Users on 1.2.0, 1.3.0, or 1.3.1 must install this release manually once; later updates can install through Sparkle.

# NOVA Copilot Version 1.3.1

- Fixes launch failure by adding the app’s embedded `Frameworks` directory to the runtime library search paths, so macOS can load Sparkle.
- Increments the marketing version to 1.3.1 and build number to 5.
- Users on 1.2.0 or the broken 1.3.0 build must install this release manually once; later updates can install through Sparkle.

# NOVA Copilot Version 1.3.0

- Checks the signed GitHub-hosted Sparkle appcast once per day and includes a manual **Check for Updates…** menu item.
- Prompts before downloading and installing an update; verifies the signed feed and update archive before installation.
- Supports sandboxed installation through Sparkle’s installer service.
- Sets the marketing version to 1.3.0 and build number to 4.
- Existing 1.2.0 installs must install 1.3.0 manually once to receive future in-app updates.

# NOVA Copilot Version 1.2.0

- Keeps a labeled NOVA control in the macOS menu bar alongside the global shortcut.
- Adds a right-edge handle that opens the assistant with a spring-slide animation and returns it to the edge when dismissed.
- Starts with the assistant tucked away, ready to open from the menu bar, screen edge, Dock, or keyboard shortcut.
- Sets the marketing version to 1.2.0 and build number to 3.

# NOVA Copilot Version 1.1.2

- Runs as a regular macOS app with a Dock icon while retaining the menu-bar sparkle and global shortcut.
- Adds a standard app menu and a Dock-click reopen action for the floating panel.
- Uses the macOS template sparkle glyph for reliable light/dark menu-bar contrast.
- Enables the hardened runtime for Release builds to prepare for Apple notarization.
- Documents the Developer ID signing and notarization steps required for a no-warning shareable build.
- Sets the marketing version to 1.1.2 and build number to 2.

# NOVA Copilot Version 1.1.1

- Based on Version 1.1.0 and retains the original AppKit `NSApplication` / `AppDelegate` startup architecture.
- Adds an explicit, standard Xcode `BuildableProductRunnable` to the shared scheme's `LaunchAction`, pointing to the existing `NOVA Copilot.app` target (blueprint ID `E10000000000000000000001`).
- Keeps the original product name, bundle identifier, executable naming, entitlements, target membership, source files, and assets.
- Retains the `NovaChatModel` initializer correction, Carbon buffer-size type correction, immutable hot-key ID, and removal of redundant `await` expressions.
- Sets the marketing version to 1.1.1.

Validation performed: project/scheme structure and references, property-list entitlements, asset JSON and referenced image files, Swift syntax parsing, and ZIP integrity. A native macOS Xcode build and launch cannot be executed in this environment and must still be verified on macOS.
