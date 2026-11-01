import AppKit
import Carbon
import SwiftUI

private func novaCopilotHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var pressedID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard result == noErr, pressedID.signature == OSType(0x4E4F5641), pressedID.id == 1 else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.togglePanel() }
    return noErr
}

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            orderOut(nil)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let chatModel = NovaChatModel()
    private let panelState = PanelState()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createPanel()
        createApplicationMenu()
        createMenuBarItem()
        registerGlobalHotKey()
        panelState.onPinChanged = { [weak self] pinned in
            self?.panel.level = pinned ? .floating : .normal
        }

        // Show the assistant immediately, while keeping the regular app
        // available from both the Dock and the menu bar.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        showPanel()
        return false
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        placePanelAtRightEdgeIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func hidePanel() { panel.orderOut(nil) }

    private func createApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "NOVA Copilot")

        let aboutItem = NSMenuItem(
            title: "About NOVA Copilot",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide NOVA Copilot",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let quitItem = NSMenuItem(
            title: "Quit NOVA Copilot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.title = "NOVA Copilot"
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenu = NSMenu(title: "Window")
        let showItem = NSMenuItem(title: "Show NOVA Copilot", action: #selector(showPanelFromMenu), keyEquivalent: "")
        showItem.target = self
        windowMenu.addItem(showItem)

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showPanelFromMenu() { showPanel() }

    private func createMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            // Menu bar items should use a template image so macOS can draw
            // them with enough contrast in both light and dark menu bars.
            let menuBarImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NOVA Copilot")
            menuBarImage?.isTemplate = true
            menuBarImage?.size = NSSize(width: 16, height: 16)
            button.image = menuBarImage
            button.toolTip = "NOVA Copilot · ⌘⇧Space"
            button.target = self
            button.action = #selector(menuBarButtonPressed)
        }
    }

    @objc private func menuBarButtonPressed() { togglePanel() }

    private func createPanel() {
        let rect = NSRect(x: 0, y: 0, width: 425, height: 690)
        panel = FloatingPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "NOVA Copilot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.975, alpha: 1)
        panel.hasShadow = true
        panel.minSize = NSSize(width: 370, height: 500)
        panel.level = panelState.isPinned ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.setFrameAutosaveName("NOVACopilotFloatingPanel")
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: AssistantView(
            model: chatModel,
            panelState: panelState,
            onHide: { [weak self] in self?.hidePanel() },
            onQuit: { NSApp.terminate(nil) }
        ))
        placePanelAtRightEdgeIfNeeded()
    }

    private func placePanelAtRightEdgeIfNeeded() {
        if panel.setFrameUsingName("NOVACopilotFloatingPanel") { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { panel.center(); return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = visible.maxX - frame.width - 16
        let y = visible.maxY - frame.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 16, y)))
    }

    private func registerGlobalHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            novaCopilotHotKeyHandler,
            1,
            &type,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard installStatus == noErr else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F5641), id: 1)
        // Default shortcut: Command + Shift + Space.
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }
}
