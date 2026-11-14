# NOVA Copilot for macOS 1.6.9

- Fixes the Sparkle installer connection by resolving the sandboxed helper service names in the signed app entitlements.
- Keeps update archive and appcast EdDSA signatures enabled.

Build 29 · macOS 13 or later

Users on 1.6.7 or 1.6.8 must install this release from the DMG once. Those builds contain unresolved Sparkle helper names, so their in-app installer cannot complete. In-app updates work again after installing 1.6.9.
