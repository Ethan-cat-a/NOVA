# NOVA Copilot

**Your AI copilot, one shortcut away.**

NOVA Copilot is available as two separate desktop editions. Choose the version for your computer:

| Edition | Platform | Version | Project |
| --- | --- | --- | --- |
| **NOVA Copilot for macOS** | macOS 13+, Apple silicon and Intel | 1.2.0 | Native Swift / AppKit app |
| **NOVA Copilot for Windows** | Windows 10 / 11, including Lenovo ThinkPad | 1.0.0 | Separate Python / Tkinter app |

## Choose your edition

### macOS

Use the native Mac application, built with Swift and AppKit.

- [macOS setup guide and features](NOVA%20Copilot/README.md)
- [Download NOVA Copilot 1.2.0 for Mac (.dmg)](https://github.com/Ethan-cat-a/NOVA/releases/download/v1.2.0/NOVA-Copilot-1.2.0.dmg)
- [macOS source project](NOVA%20Copilot.xcodeproj)

### Windows / Lenovo ThinkPad

Use the independent Windows edition. It has its own setup guide and source package; it is not the macOS Swift app.

- [Windows setup guide](NOVA%20Copilot%20Windows/README.md)
- [Windows source folder](NOVA%20Copilot%20Windows/)
- [Windows 1.0.0 release notes](NOVA%20Copilot%20Windows/RELEASE_NOTES_v1.0.0.md)

**Windows build note:** Build it on a Windows PC with Python 3.10 or newer to generate `NOVA Copilot.exe`. The executable is not prebuilt or publicly signed yet, and the package has not yet been tested on a physical ThinkPad.

## Keep the editions separate

- `NOVA Copilot/` and `NOVA Copilot.xcodeproj/` contain the original macOS Swift application.
- `NOVA Copilot Windows/` contains the independent Windows application.

Both editions connect to the existing Nova V8 chat backend. Their UI code, build process, and local chat storage are separate.
