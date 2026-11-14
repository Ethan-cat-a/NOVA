# NOVA Copilot for macOS 1.6.7

- Fixes a launch crash on ad-hoc signed builds. The app no longer opts into Hardened Runtime library validation, which rejected the embedded Sparkle framework when the app had no Apple Developer ID Team ID.
- Re-signs only the outer app bundle during packaging, preserving Sparkle's separately signed helper tools.
- Keeps Sparkle EdDSA signatures on the update ZIP and appcast.
- Build number: 27.

The app remains ad-hoc signed and is not notarized with an Apple Developer ID.
