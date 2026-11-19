# NOVA Copilot for macOS 2.0.0

## Reviewable project patches

CS Agent can now prepare a code patch for a project folder you choose.

- Review the supported source-file list and choose exactly which files NOVA may read for the request.
- NOVA proposes a unified diff for existing files only. The app checks that paths stay in the selected project and that the source has not changed since it was read.
- Inspect each file’s diff, select the files you want, and confirm before applying. NOVA saves local backups first.
- The workflow does not run commands, builds or tests, and does not commit or push.

## Version

- macOS marketing version: **2.0.0**
- Build number: **42**
- The release includes the universal app for Apple silicon and Intel Macs running macOS 13 or later.
- The app is ad-hoc signed, not signed with an Apple Developer ID, and not notarized; macOS may ask you to approve it on first launch.
